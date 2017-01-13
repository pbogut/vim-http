let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#vim_http#new()
let s:Base64 = s:V.import('Data.Base64')

function! s:new_request() abort
    let l:response = { 
                \ 'method': 'GET',
                \ 'headers': {},
                \ 'uri': '',
                \ 'content': '',
                \ 'version': '1.1',
                \ 'meta': {
                \   'follow': 0,
                \   }
                \ }
    return l:response
    
endfunction

let s:uri_line_pattern = '^\(OPTIONS\|GET\|HEAD\|POST\|PUT\|DELETE\|TRACE\|CONNECT\) \(.*\) HTTP/\([0-9.]\+\)$'
let s:header_line_pattern = '^\([^:]\+\): \(.*\)$'

function! s:parse_request_buffer(buffer, follow) abort
    let l:request = s:new_request()
    if a:follow == 1
        let l:request.meta.follow = 1
    end
    
    let l:lines = getbufline(a:buffer, 0, '$')
    
    if len(l:lines) < 0 
        throw 'No lines in buffer :('
    endif

    let l:uri_line = l:lines[0]
    let l:uri_line_matches = matchlist(l:uri_line, s:uri_line_pattern)

    if len(l:uri_line_matches) == 0 
        throw 'Unable to parse first line of request'
    end

    let l:request.method = l:uri_line_matches[1]
    let l:request.uri = l:uri_line_matches[2]
    let l:request.version = l:uri_line_matches[3]

    let l:in_content = 0
    let l:first_content_line = 1
    for l:line in l:lines[0:]
        if l:in_content == 0 && l:line =~ '^\s*$'
            let l:in_content = 1
        end
        if l:in_content == 0
            let l:header_matches = matchlist(l:line, s:header_line_pattern)

            if len(l:header_matches) > 0
                let l:header_key = l:header_matches[1]
                let l:header_value = l:header_matches[2]
                if has_key(l:request.headers, l:header_key) == 0
                    let l:request.headers[l:header_key] = []
                endif
                let l:request.headers[l:header_key] += [l:header_value]
            endif
        else
            if l:first_content_line && l:line =~ '^\s*$'
                continue
            endif
            if l:first_content_line
                let l:first_content_line = 0
            else
                let l:request.content .= "\r\n"
            endif
            let l:request.content .= l:line
        endif
    endfor

    return l:request
endfunction

function! s:in_curl_format(request) abort
    let l:curl_fmt = 'curl%s%s%s%s %s'

    let l:flags = ' -si' 

    if a:request.meta.follow == 1
        let l:flags = l:flags . 'L'
    endif

    let l:method = printf(' -X %s', a:request.method)

    let l:url = shellescape(a:request.uri)

    let l:headers = ''

    for [l:header_key, l:header_value_list] in items(a:request.headers)
        for l:header_value in l:header_value_list
            let l:headers = l:headers .
                        \ ' -H "' .
                        \ printf('%s: %s', l:header_key, l:header_value) .
                        \ '"'
        endfor

    endfor
    
    let l:data = ''
    if len(a:request.content)
        let l:data = ' -d ' . substitute(shellescape(a:request.content), '\\\n', "\n", 'g')
    endif  

    let l:curl_request = printf(l:curl_fmt, l:flags, l:method, l:headers, l:data, l:url)

    return l:curl_request

endfunction

function! s:new_response_buffer(request_buffer, response) abort
    let l:request_buffer_name  = bufname(a:request_buffer)
    let l:buffer_name = fnamemodify(l:request_buffer_name, ":r") . '.response.' . localtime() . '.http'
    execute 'new ' . l:buffer_name
    set ft=http

    let l:response_lines = split(a:response, "\\(\r\n\\|\n\\)")

    call append(0, l:response_lines)
    norm! G"_ddgg

endfunction

function! http#do_buffer(follow) abort
    if g:vim_http_clean_before_do
      call http#clean()
    end
    let l:buffer = bufnr('')
    let l:request = s:parse_request_buffer(l:buffer, a:follow)
    let l:curl = s:in_curl_format(l:request)
    let l:response = system(l:curl)
    call s:new_response_buffer(l:buffer, l:response)
endfunction

function! http#show_curl() abort
    let l:buffer = bufnr('')
    let l:request = s:parse_request_buffer(l:buffer, 0)
    let l:curl = s:in_curl_format(l:request)
    echo l:curl
endfunction

function! http#show_request() abort
    let l:buffer = bufnr('')
    let l:request = s:parse_request_buffer(l:buffer, 0)
    echo l:request
endfunction

function! http#clean() abort
  let l:buffer = bufnr('')
  let l:request = s:parse_request_buffer(l:buffer, 0)

  if index(['1.1', '2.0'], l:request.version) != -1 && !has_key(l:request.headers, 'Host')
    let l:matches = matchlist(l:request.uri, '^\([^:]\+://\)\([^/]\+\)')
    let l:host = l:matches[2]
    if len(l:host)
      call append(1, 'Host: ' . l:host)
    endif
  endif

  if !has_key(l:request.headers, 'Content-Length') && len(l:request.content)
    let l:content_length = len(l:request.content)
    call append(1 + len(l:request.headers), 'Content-Length: ' . l:content_length)
  endif
endfunction

function! http#auth() abort
  let l:buffer = bufnr('')
  let l:request = s:parse_request_buffer(l:buffer, 0)

  let l:method = input('method [Basic]: ')
  if len(l:method) == 0
    let l:method = 'Basic'
  end
  let l:user = input('user: ')
  let l:password = input('password: ')
  let l:encoded = s:Base64.encode(l:user . ':' . l:password)
  let l:header = 'Authorization: ' . l:method . ' ' . l:encoded
  call append(1 + len(l:request.headers), l:header)
endfunction

" Teardown:{{{1
let &cpo = s:save_cpo