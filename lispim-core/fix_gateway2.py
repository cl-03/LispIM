#!/usr/bin/env python3

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix line 605 - separate comment from code
old1 = b";; \xe5\x9c\xa8\xe7\xba\xbf\xe7\x8a\xb6\xe6\x80\x81      ((+ws-msg-presence+)\r\n"
new1 = b";; \xe5\x9c\xa8\xe7\xba\xbf\xe7\x8a\xb6\xe6\x80\x81\r\n      ((+ws-msg-presence+)\r\n"

# Fix line 607 - separate comment from code
old2 = b";; \xe8\xbe\x93\xe5\x85\xa5\xe7\x8a\xb6\xe6\x80\x81      ((+ws-msg-typing+)\r\n"
new2 = b";; \xe8\xbe\x93\xe5\x85\xa5\xe7\x8a\xb6\xe6\x80\x81\r\n      ((+ws-msg-typing+)\r\n"

content = content.replace(old1, new1).replace(old2, new2)

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)

print('Fixed lines 605 and 607')
