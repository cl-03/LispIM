#!/usr/bin/env python3
import re

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read()

# Fix the corrupted line 370-371 - remove the comment prefix and keep only the defvar
old = b";; WebSocket \xe8\xbf\x9e\xe6\x8e\xa5\xe5\x93\x88\xe5\xb8\x8c\xe8\xa1\x8c(defvar *ws-connections* (make-hash-table :test 'equal)\r\n  \"WebSocket connection hash table\")\r"
new = b"(defvar *ws-connections* (make-hash-table :test 'equal)\r\n  \"WebSocket connection hash table\")\r"

if old in content:
    content = content.replace(old, new)
    print('Fixed line 370-371')
else:
    print('Pattern not found, searching for it...')
    # Try to find what's actually there
    idx = content.find(b'ws-connections')
    if idx >= 0:
        print(f'Found at index {idx}')
        print(f'Context: {content[idx-50:idx+100]}')

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'wb') as f:
    f.write(content)
