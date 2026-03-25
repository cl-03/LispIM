#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 1687 - add closing parens for handler-case and defun
old = b'      (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c))))\r\n\r\n;; Auth API v1 - Register'
new = b'      (encode-api-response (make-api-error "INTERNAL_ERROR" (condition-message c)))))\r\n\r\n;; Auth API v1 - Register'

if old in content:
    content = content.replace(old, new)
    print('Fixed line 1687')
else:
    print('Pattern not found')
    # Show what's actually there
    lines = content.split(b'\n')
    print(f'Line 1687: {lines[1686]}')
    print(f'Line 1688: {lines[1687]}')
    print(f'Line 1689: {lines[1688]}')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
