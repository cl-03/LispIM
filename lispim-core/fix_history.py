#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix api-get-history-handler - add closing parens after line 1622
old = b'      (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))\r\n\r\n;; Chat API v1 - Send Message'
new = b'      (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))\r\n\r\n;; Chat API v1 - Send Message'

if old in content:
    content = content.replace(old, new)
    print('Fixed api-get-history-handler')
else:
    print('Pattern not found')
    # Show what's actually there
    lines = content.split(b'\n')
    print(f'Line 1622: {lines[1621]}')
    print(f'Line 1623: {lines[1622]}')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
