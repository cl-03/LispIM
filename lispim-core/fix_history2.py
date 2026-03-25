#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix api-get-history-handler - add one more closing paren
old = b'      (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))\r\n'
new = b'      (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))))\r\n'

if old in content:
    content = content.replace(old, new)
    print('Fixed api-get-history-handler - added one more closing paren')
else:
    print('Pattern not found')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
