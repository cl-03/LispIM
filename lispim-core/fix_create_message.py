#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 32 - add one more closing paren
old = b'          nil))))\r\n'
new = b'          nil)))))\r\n'

if old in content:
    content = content.replace(old, new)
    print('Fixed line 32 - added one closing paren')
else:
    print('Pattern not found')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
