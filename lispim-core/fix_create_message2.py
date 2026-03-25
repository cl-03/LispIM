#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Revert line 32 - remove the extra closing paren we added
old = b'          nil)))))\r\n'
new = b'          nil))))\r\n'

if old in content:
    content = content.replace(old, new)
    print('Reverted line 32')
else:
    print('Pattern not found')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
