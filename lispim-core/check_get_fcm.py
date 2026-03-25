#!/usr/bin/env python3
"""Check and fix api-get-fcm-tokens-handler function"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check from line 2264 to end
start_line = 2263  # 0-indexed
open_count = 0
close_count = 0
depth = 0

for i in range(start_line, len(lines)):
    line = lines[i]
    line_open = line.count('(')
    line_close = line.count(')')
    open_count += line_open
    close_count += line_close
    depth += line_open - line_close
    if i < len(lines) - 1 and (line_open > 0 or line_close > 0):
        print(f"Line {i+1}: +{line_open}/-{line_close} = depth {depth}")

print(f"\nTotal: open={open_count}, close={close_count}, diff={open_count - close_count}")
print(f"Final depth: {depth} (should be 0 for complete function)")

if depth > 0:
    print(f"Need {depth} more closing parens")
