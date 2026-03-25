#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 1682 - remove one extra closing paren
old = b'                  (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required")))))))))\r\n'
new = b'                  (encode-api-response (make-api-error "AUTH_REQUIRED" "Authentication required"))))))))\r\n'

if old in content:
    content = content.replace(old, new)
    print('Fixed line 1682 - removed one extra closing paren')
else:
    print('Pattern not found')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
