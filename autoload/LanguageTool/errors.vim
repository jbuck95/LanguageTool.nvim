" LanguageTool: Grammar checker in Vim for English, French, German, etc.
" Maintainer:   Thomas Vigouroux <tomvig38@gmail.com>
" Last Change:  2019 Oct 14
" Version:      1.0
"
" License: {{{1
"
" The VIM LICENSE applies to LanguageTool.nvim plugin
" (see ":help copyright" except use "LanguageTool.nvim" instead of "Vim").
"
" }}} 1

" This functions finds the error at point
function! LanguageTool#errors#find() "{{{1
    if !exists('b:errors')
        return {}
    endif
    let line_byte_index = line2byte('.')
    let current_col = byteidxcomp(getline('.'), col('.'))

    let current_byte_idx = line_byte_index + current_col

    for l:error in b:errors
        if error.start_byte_idx <= current_byte_idx && error.stop_byte_idx >= current_byte_idx
            return l:error
        endif
    endfor
    return {}
endfunction


function! LanguageTool#ui#ShowSuggestions() abort
  let l:errors = get(b:, 'languagetool_errors', [])
  let l:cursor_pos = getpos('.')
  let l:line = l:cursor_pos[1]
  let l:col = l:cursor_pos[2]
  for l:err in l:errors
    if l:err.line == l:line && l:err.col <= l:col && l:col <= l:err.col + l:err.length
      if has_key(l:err, 'suggestions') && len(l:err.suggestions) > 0
        let l:choice = inputlist(['Select a suggestion:'] + l:err.suggestions)
        if l:choice > 0 && l:choice <= len(l:err.suggestions)
          let l:suggestion = l:err.suggestions[l:choice - 1]
          call nvim_buf_set_text(0, l:err.line - 1, l:err.col - 1, l:err.line - 1, l:err.col - 1 + l:err.length, [l:suggestion])
        endif
      else
        echo "No suggestions available"
      endif
      return
    endif
  endfor
  echo "No error under cursor"
endfunction

" This functions appends a pretty printed version of current error at the end of the current buffer
" flags can be used to customize how pretty print is done, see doc for more information
" set the third argument as start line of the pp to highlight context
function! LanguageTool#errors#getSummary(error, flags) "{{{1
    let l:pretty_print = []

    if empty(a:flags)
        let l:flags = 'TMcCE{irRu}'
    else
        let l:flags = a:flags
    endif

    " Flags construction
    let l:flag_pp_part = [
                \ ['T{s}', [(a:error.index + 1) . ' / ' . a:error.nr_errors
                    \ . ' @ ' . a:error.fromy . 'L ' . a:error.fromx . 'C : '
                    \ . ((has_key(a:error, 'shortMessage') && !empty(a:error.shortMessage)) ?
                    \ a:error.shortMessage : a:error.rule.id)]],
                \ ['\(T{s}\)\@!\&T', ['Error:      '
                    \ . (a:error.index + 1) . ' / ' . a:error.nr_errors
                    \ . ' @ ' . a:error.fromy . 'L ' . a:error.fromx . 'C']],
                \ ['M{s}', (has_key(a:error, 'shortMessage') && !empty(a:error.shortMessage)) ? 
                    \ ['Message:    '     . a:error.shortMessage] : 
                    \ []],
                \ ['\(M{s}\)\@!\&M', ['Message:    '     . a:error.message]],
                \ ['c', ['Context:    ' . a:error.context.text]],
                \ ['C', has_key(a:error, 'replacements') ? 
                    \ ['Corrections:'] + map(copy(a:error.replacements), '"  " . v:val.value') :
                    \ []],
                \ ['E{.\+}', ['More:']],
                \ ['E{.*i.*}', has_key(a:error.rule.category, 'id') ?
                    \ ['  Category: ' . a:error.rule.category.id] :
                    \ []],
                \ ['E{.*r.*}', ['  Rule:     ' . a:error.rule.id]],
                \ ['E{.*R.*}', has_key(a:error.rule, 'subId') ? 
                    \ ['  Subrule:  ' . a:error.rule.subId] :
                    \ []],
                \ ['E{.*u.*}' , has_key(a:error.rule, 'urls') ?
                    \ ['  URLs:'] + map(copy(a:error.rule.urls), '"    " . v:val.value') :
                    \ []]
                \ ]

    " Iterate over the flags and build the requested summary
    for [l:flag_part, l:str_to_add] in l:flag_pp_part
        if l:flags =~# '\m' . l:flag_part && !empty(l:str_to_add)
            let l:pretty_print += l:str_to_add

            " if the flag is the context, we have to highlight it
            if l:flag_part ==# 'c'
                let l:re =
                            \ '\mError:\s\+' . (a:error.index + 1)
                            \ . '\_.\{-}Context:.*\zs' . LanguageTool#errors#getText(a:error) . '\ze'
                            \ . '\_.\{-}\_^\_$'

                if a:error.rule.id =~# 'HUNSPELL_RULE\|HUNSPELL_NO_SUGGEST_RULE\|MORFOLOGIK_RULE_\|_SPELLING_RULE\|_SPELLER_RULE'
                    call matchadd('LanguageToolSpellingError', l:re)
                else
                    call matchadd('LanguageToolGrammarError', l:re)
                endif
            endif
        endif
    endfor

    return l:pretty_print + ['']
endfunction

" Return a regular expression used to highlight a grammatical error
" at line a:line in text.  The error starts at character a:start in
" context a:context and its length in context is a:len.
function! LanguageTool#errors#highlightRegex(error)  "{{{1
    " The location prefix is used to match only at the point of the actual
    " error and not multiple times accross the line/text
    if a:error.fromy == a:error.toy
        let l:location_prefix = '\%' . a:error.fromy . 'l'
                    \ . '\%>' . (a:error.fromx - 1) . 'c'
                    \ . '\%<' . (a:error.tox + 1) . 'c'
                    \ . '\&'
    else
        let l:location_prefix = '\(\%' . a:error.fromy . 'l\%>' . (a:error.fromx - 1) . 'c\|'
                    \ . '\%>' . a:error.fromy . 'l\%<' . a:error.toy . 'l\|'
                    \ . '\%' . a:error.toy . 'l\%<' . (a:error.tox + 1) . 'c\)\&'
    endif

    " The substitute allows matching errors which span multiple lines.
    " We use \< and \> because all errors start at the beginning of
    " a word and end at the end of a word
    return  '\V' . l:location_prefix . '\<'
    \     . LanguageTool#errors#getText(a:error)
    \     . '\>\ze'
endfunction "}}}

" This function returns the actual errored text of a:error
function! LanguageTool#errors#getText(error) "{{{
    let l:start_idx     = byteidxcomp(a:error.context.text, a:error.context.offset)
    let l:end_idx       = byteidxcomp(a:error.context.text, a:error.context.offset + a:error.context.length) - 1

    return substitute(escape(a:error.context.text[l:start_idx : l:end_idx], '''.\'), ' ', '\\_\\s', 'g')
endfunction "}}}

" This function uses suggestion sug_id to fix error error
function! LanguageTool#errors#fix(error, sug_id) "{{{1
    let l:location_regex = LanguageTool#errors#highlightRegex(a:error)
    let l:fix = a:error.replacements[a:sug_id].value

    call win_gotoid(a:error.source_win)
    " This is temporary, we might want to use / only if it is not present
    " in any of l:location_regex and l:fix
    execute a:error.fromy . ',' . a:error.toy . 's/' . l:location_regex . '/' . l:fix . '/'
endfunction

" This function is used on the description of an error to get the underlying data
function! LanguageTool#errors#errorAtPoint() "{{{1
    let l:save_cursor = getpos('.')
    norm! $
    if search('^Error:\s\+', 'beW') > 0
        let l:error_idx = expand('<cword>')
        let l:error = b:errors[l:error_idx - 1]
        call setpos('.', l:save_cursor)
        return l:error
    endif
    return {}
endfunction

" This function returns the index of the suggestion at point
function! LanguageTool#errors#suggestionAtPoint() "{{{1
    return line('.') - search('Corrections:', 'bn') - 1
endfunction

" Jump to a grammar mistake (called when pressing <Enter>
" on a particular error in scratch buffer).
function! LanguageTool#errors#jumpToCurrentError() "{{{1
    let l:error = LanguageTool#errors#errorAtPoint()
    if !empty(l:error)
        let l:line = l:error.fromy
        let l:col  = l:error.fromx
        let l:rule = l:error.rule.id
        if exists('*win_gotoid')
            call win_gotoid(l:error.source_win)
        else
            exe l:error.source_win . ' wincmd w'
        endif
        exe 'norm! ' . l:line . 'G0'
        if l:col > 0
            exe 'norm! ' . (l:col  - 1) . 'l'
        endif

        echon 'Jump to error ' . LanguageTool#errors#getSummary(l:error, 'T{s}')[0]
        norm! zz
    endif
endfunction

" This function returns the line number of the previous start of error summary
function! LanguageTool#errors#previousSummary()
    return search('^Error:\s\+', 'bn')
endfunction


" This function returns the line number of the next start of error summary
function! LanguageTool#errors#nextSummary()
    return search('^Error:\s\+', 'n')
endfunction
