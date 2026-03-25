#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix api-register-fcm-token-handler - add closing parens after line 2231
old1 = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))\r\n\r\n;; DELETE'
new1 = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))\r\n\r\n;; DELETE'

# Fix api-remove-fcm-token-handler - add closing parens after line 2261
old2 = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))\r\n\r\n;; GET'
new2 = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))\r\n\r\n;; GET'

count = 0
if old1 in content:
    content = content.replace(old1, new1)
    count += 1
    print('Fixed api-register-fcm-token-handler')
else:
    print('Pattern 1 not found')

if old2 in content:
    content = content.replace(old2, new2)
    count += 1
    print('Fixed api-remove-fcm-token-handler')
else:
    print('Pattern 2 not found')

print(f'Fixed {count} functions')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
