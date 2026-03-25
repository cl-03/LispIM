#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    content = f.read()

# Track depth
depth = 0
in_string = False
escape_next = False

for c in content:
    if escape_next:
        escape_next = False
        continue
    if c == chr(92):  # backslash
        escape_next = True
        continue
    if c == '"':
        in_string = not in_string
        continue
    if not in_string:
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1

print(f'Final depth: {depth}')
print('Expected: 0 (all structures closed)')
