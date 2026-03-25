#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix end of file - add missing closing parens before the final comment
old = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))\r\n\r\n;;; End of gateway.lisp'
new = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))\r\n\r\n;;; End of gateway.lisp'

if old in content:
    content = content.replace(old, new)
    print('Fixed end of file - added one closing paren')
else:
    print('Pattern not found')
    # Show what's actually at the end
    lines = content.split(b'\n')
    for i in range(len(lines)-5, len(lines)):
        print(f'{i+1}: {lines[i]}')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
