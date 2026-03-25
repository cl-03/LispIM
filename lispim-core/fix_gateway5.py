#!/usr/bin/env python3

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 668 - separate comment from code
old1 = b";; \xe5\x8f\x91\xe9\x80\x81\xe6\xb6\x88\xe6\x81\xaf      (handler-case\r\n"
new1 = b";; \xe5\x8f\x91\xe9\x80\x81\xe6\xb6\x88\xe6\x81\xaf\r\n          (handler-case\r\n"

content = content.replace(old1, new1)

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)

print('Fixed line 668')
