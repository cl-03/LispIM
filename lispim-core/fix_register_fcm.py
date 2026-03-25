#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix api-register-fcm-token-handler - add one more closing paren
old = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))))\r\n\r\n;; DELETE'
new = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))))\r\n\r\n;; DELETE'

if old in content:
    content = content.replace(old, new)
    print('Fixed api-register-fcm-token-handler')
else:
    print('Pattern not found')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
