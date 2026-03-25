#!/usr/bin/env python3
"""Check paren balance for api-get-history-handler function"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check from line 1586 to line 1623
open_count = 0
close_count = 0
depth = 0

for i in range(1585, min(1624, len(lines))):
    line = lines[i]
    line_open = line.count('(')
    line_close = line.count(')')
    open_count += line_open
    close_count += line_close
    depth += line_open - line_close
    if line_open > 0 or line_close > 0:
        print(f"Line {i+1}: +{line_open}/-{line_close} = depth {depth} | {line.rstrip()[:70]}")

print(f"\nTotal: open={open_count}, close={close_count}, diff={open_count - close_count}")
print(f"Final depth: {depth} (should be 0 for complete function)")
