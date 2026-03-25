#!/usr/bin/env python3
# Check parenthesis balance for api-send-message-handler function

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Count parens from line 1624 (defun) to line 1686
open_count = 0
close_count = 0

for i in range(1623, min(1687, len(lines))):
    line = lines[i]
    for c in line:
        if c == '(':
            open_count += 1
        elif c == ')':
            close_count += 1

    if open_count < close_count:
        print(f'Line {i+1}: More closes than opens! open={open_count}, close={close_count}')
        print(f'  Content: {line.rstrip()[:80]}')
        break

print(f'Total: open={open_count}, close={close_count}, diff={open_count - close_count}')
