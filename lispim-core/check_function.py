#!/usr/bin/env python3
"""Check paren balance for api-send-message-handler function"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check from line 1624 (defun) to line 1688 (end of function)
open_count = 0
close_count = 0
depth = 0

for i in range(1623, min(1689, len(lines))):
    line = lines[i]
    line_open = line.count('(')
    line_close = line.count(')')
    open_count += line_open
    close_count += line_close
    depth += line_open - line_close
    if line_open > 0 or line_close > 0:
        print(f"Line {i+1}: +{line_open}/-{line_close} = depth {depth} | {line.rstrip()[:60]}")

print(f"\nTotal: open={open_count}, close={close_count}, diff={open_count - close_count}")
print(f"Final depth: {depth} (should be 0 for complete function)")
