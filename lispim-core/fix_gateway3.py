#!/usr/bin/env python3

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 582 - separate comment from code
old1 = b";; \xe5\x8f\x91\xe9\x80\x81ACK \xe5\xa6\x82\xe6\x9e\x9c\xe9\x9c\x80\xe8\xa6\x81    (when (and ack-required message-id)\r\n"
new1 = b";; \xe5\x8f\x91\xe9\x80\x81ACK \xe5\xa6\x82\xe6\x9e\x9c\xe9\x9c\x80\xe8\xa6\x81\r\n    (when (and ack-required message-id)\r\n"

content = content.replace(old1, new1)

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)

print('Fixed line 582')
