#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix api-remove-fcm-token-handler - add one more closing paren
old = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))))\r\n\r\n;; GET'
new = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))))\r\n\r\n;; GET'

if old in content:
    content = content.replace(old, new)
    print('Fixed api-remove-fcm-token-handler')
else:
    print('Pattern not found - trying alternate')
    # Maybe the comment is different
    old2 = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))))\r\n'
    new2 = b'        (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))))\r\n'
    if old2 in content:
        content = content.replace(old2, new2)
        print('Fixed with alternate pattern')
    else:
        print('Alternate pattern not found either')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
