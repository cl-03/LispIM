#!/usr/bin/env python3
"""Check paren balance for api-remove-fcm-token-handler function"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find the function end
start_line = 2233  # 0-indexed
end_line = start_line + 1

for i in range(start_line + 1, len(lines)):
    line = lines[i].strip()
    if line.startswith('(defun ') or line.startswith('(hunchentoot:define') or line.startswith(';;;'):
        end_line = i
        break

print(f"Function spans lines {start_line+1} to {end_line}")

# Check paren balance
open_count = 0
close_count = 0
depth = 0

for i in range(start_line, min(end_line, len(lines))):
    line = lines[i]
    line_open = line.count('(')
    line_close = line.count(')')
    open_count += line_open
    close_count += line_close
    depth += line_open - line_close

print(f"Total: open={open_count}, close={close_count}, diff={open_count - close_count}")
print(f"Final depth: {depth} (should be 0 for complete function)")

if depth != 0:
    print(f"Need {-depth} more closing parens" if depth > 0 else f"Have {-depth} extra closing parens" if depth < 0 else "")
