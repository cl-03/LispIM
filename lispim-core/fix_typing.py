#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 714 - the parens are part of the comment, not the code structure
# The when body needs proper closing
old = b'      ;; TODO: \xe5\xb9\xbf\xe6\x92\xad\xe8\xbe\x93\xe5\x85\xa5\xe7\x8a\xb6\xe6\x80\x81      )))\r\n'
new = b'      ;; TODO: \xe5\xb9\xbf\xe6\x92\xad\xe8\xbe\x93\xe5\x85\xa5\xe7\x8a\xb6\xe6\x80\x81\xe7\xbb\x99\xe4\xbc\x9a\xe8\xaf\x9d\xe4\xb8\xad\xe7\x9a\x84\xe5\x85\xb6\xe4\xbb\x96\xe7\x94\xa8\xe6\x88\xb7\r\n      )))\r\n'

if old in content:
    content = content.replace(old, new)
    print('Fixed line 714 - separated comment from closing parens')
else:
    print('Pattern not found')
    # Show what's actually there
    lines = content.split(b'\n')
    print(f'Line 714: {lines[713]}')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
