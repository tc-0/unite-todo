let s:save_cpo = &cpo
set cpo&vim

let s:source = {
      \ 'name':'todo',
      \}

function! s:source.gather_candidates(args, context)
  let candidates = []
  let list = empty(a:args) ? s:all() : s:select(s:pattern(a:args))
  for todo in list
    call add(candidates, {
          \   "word": join([todo.status, todo.title, join(todo.tags)]),
          \   "kind": "todo",
          \   "action__path": todo.note,
          \   "source__line": todo.line,
          \ })
    unlet todo
  endfor
  return candidates
endfunction

function! s:pattern(args)
  let arg = a:args[0]
  if arg ==? 'done' 
    return 'v:val.status =~ "[X]"'
  elseif arg ==? 'undone' 
    return 'v:val.status !~ "[X]"'
  elseif arg ==? 'tag' 
    if len(a:args) < 2 || empty(a:args[1])
      return ''
    endif
    return 'index(v:val.tags, "@'.a:args[1].'") != -1'
  endif
  return ''
endfunction

command! -nargs=0 UniteTodoAddSimple call s:add([input('Todo:')])
nnoremap <Space>a :<C-u>UniteTodoAddSimple<CR>
command! -nargs=0 -range UniteTodoAddRange call s:add(reverse(getbufline('%', <line1>, <line2>)))
command! -nargs=0 UniteTodoAddBuffer call s:add(reverse(getbufline('%', 1, '$')))
let &cpo = s:save_cpo

" TODO defineのほうが呼ばれない
call unite#define_source(s:source)
unlet s:source

" =====================================================
" TODO 複数のファイルで共通的に使いたいので、どこか別のファイルに置きたい
let s:save_cpo = &cpo
set cpo&vim
let s:todo_file = g:unite_data_directory . '/todo/todo.txt'
let s:note_dir = g:unite_data_directory . '/todo/note'

function! s:struct(line)
  let words = split(a:line, ',') 
  if len(words) < 4
    let tags = [] 
  elseif len(words) == 4
    let tags = [words[3]] 
  else
    let tags = words[3:]
  endif
  return {
        \ 'id': words[0],
        \ 'status': words[1],
        \ 'title': words[2],
        \ 'tags': tags,
        \ 'note': s:note_dir . '/' . words[0] . ".txt",
        \ 'line': a:line,
        \ }
endfunction

function! s:select(pattern)
  let todo_list = map(readfile(s:todo_file), 's:struct(v:val)')
  return empty(a:pattern) ? todo_list : filter(todo_list, a:pattern)
endfunction

function! s:all()
  return s:select([])
endfunction

function! s:update(structs)
  call writefile(
        \ map(a:structs, 'join([v:val.id, v:val.status, v:val.title, join(v:val.tags, ",")], ",")'),
        \ s:todo_file)
endfunction

function! s:new(id, title)
  return s:struct(join([a:id, '[ ]', a:title], ','))
endfunction

" TODO もうちょい綺麗に
function! s:add(title_list)
  let size = len(a:title_list)
  if size == 0
    echo 'todo is empty'
  else
    for i in range(0, size-1)
      let title = s:trim(a:title_list[i])
      if !empty(title)
        call s:update(insert(s:all(), s:new(localtime().'_'.i, title)))
      endif
    endfor
  endif
endfunction

function! s:trim(str)
  return substitute(a:str, '^\s\+\|\s\+$', '', 'g')
endfunction

function! s:rename(todo)
  let list = []
  for todo in s:all()
    if todo.id == a:todo.id 
      call add(list, a:todo)
    else
      call add(list, todo)
    endif
  endfor
  call s:update(list)
endfunction

function! s:delete(todo)
  let note = a:todo.note
  if filewritable(note) && !isdirectory(note)
    call delete(note)
  endif
  call s:update(s:select('v:val.id !=# "'.a:todo.id.'"'))
endfunction

function! s:toggle(todo)
  let list = []
  for todo in s:all()
    if todo.id == a:todo.id 
      let todo.status = todo.status =~ '^\[X\]' ? 
            \ "[ ]" :
            \ "[X]<".strftime("%Y/%m/%d %H:%M").">"
    endif
    call add(list, todo)
  endfor
  call s:update(list)
endfunction

let s:kind = {
      \ 'name' : 'todo',
      \ 'default_action' : 'toggle',
      \ 'action_table': {},
      \ 'is_selectable': 1,
      \ 'parents': ['jump_list'],
      \}

let s:kind.action_table.edit_title = { 'description' : 'edit todo title' }
function! s:kind.action_table.edit_title.func(candidate)
  let todo = s:struct(a:candidate.source__line)
  let after = s:trim(input('Todo:' . todo.title . '->', todo.title))
  if !empty(after)
    let todo.title = after
    call s:rename(todo)
  endif
endfunction

let s:kind.action_table.add_tag = { 'description' : 'add todo tag', 'is_selectable': 1 }
function! s:kind.action_table.add_tag.func(candidates)
  let tags = s:trim(input('Tags(comma separate):'))
  if !empty(tags)
    " TODO 毎回ファイルI/Oさせてるので非効率
    for candidate in a:candidates
      let todo = s:struct(candidate.source__line)
      call extend(todo.tags, map(split(tags, ','), '"@".v:val'))
      call s:rename(todo)
    endfor
  endif
endfunction

let s:kind.action_table.edit_tag = { 'description' : 'edit todo tag' }
function! s:kind.action_table.edit_tag.func(candidate)
  let todo = s:struct(a:candidate.source__line)
  let before = join(map(todo.tags, 'substitute(v:val, "^@", "", "")'), ',')
  let after = s:trim(input('Tags(comma separate):' . before . '->', before))
  if !empty(after)
    let todo.tags = map(split(after, ','), '"@".v:val')
    call s:rename(todo)
  endif
endfunction

let s:kind.action_table.delete = { 'description' : 'delete todo', 'is_selectable': 1 }
function! s:kind.action_table.delete.func(candidates)
  if input('delete ok? [y/N]') =~? '^y\%[es]$'
    for candidate in a:candidates
      " TODO 毎回ファイルI/Oさせてるので非効率
      call s:delete(s:struct(candidate.source__line))
    endfor
  endif
endfunction

let s:kind.action_table.toggle = { 'description' : 'toggle done/undone', 'is_selectable': 1 }
function! s:kind.action_table.toggle.func(candidates)
  for candidate in a:candidates
    " TODO 毎回ファイルI/Oさせてるので非効率
    call s:toggle(s:struct(candidate.source__line))
  endfor
endfunction

let s:parent_kind = {
      \ 'is_quit': 0,
      \ 'is_invalidate_cache': 1,
      \ }
call extend(s:kind.action_table.edit_title, s:parent_kind, 'error')
call extend(s:kind.action_table.add_tag, s:parent_kind, 'error')
call extend(s:kind.action_table.edit_tag, s:parent_kind, 'error')
call extend(s:kind.action_table.delete, s:parent_kind, 'error')
call extend(s:kind.action_table.toggle, s:parent_kind, 'error')

" TODO defineのほうが呼ばれない
call unite#define_kind(s:kind)
unlet s:kind

let &cpo = s:save_cpo
unlet s:save_cpo

nnoremap <Space><Space> :<C-u>Unite todo<CR>
