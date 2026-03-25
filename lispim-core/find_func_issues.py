#!/usr/bin/env python3
"""Find functions that don't return to their starting depth"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Track depth
current_depth = 0
in_string = False
escape_next = False

func_starts = []  # (line_num, func_name, start_depth)

for i, line in enumerate(lines):
    start_depth = current_depth

    # Check for defun
    if '(defun ' in line:
        func_name = line.split('(defun ')[1].split()[0] if '(defun ' in line else 'unknown'
        func_starts.append([i+1, func_name, start_depth, -1])  # -1 means not yet ended

    for j, c in enumerate(line):
        if escape_next:
            escape_next = False
            continue
        if c == '\\':
            escape_next = True
            continue
        if c == '"':
            in_string = not in_string
            continue
        if not in_string:
            if c == '(':
                current_depth += 1
            elif c == ')':
                current_depth -= 1

    # Check if we returned to a previous depth (function ended)
    if func_starts:
        last_func = func_starts[-1]
        if last_func[3] == -1 and current_depth <= last_func[2]:
            last_func[3] = current_depth  # Mark end depth

# Find functions that don't return to their starting depth
unclosed = []
for func in func_starts:
    line_num, name, start_d, end_d = func
    if end_d != start_d:
        unclosed.append((line_num, name, start_d, end_d))

print(f"Functions that don't return to starting depth: {len(unclosed)}")
for line_num, name, start_d, end_d in unclosed[:20]:
    print(f"  Line {line_num}: {name} - depth {start_d} -> {end_d} (diff: {end_d - start_d})")

if len(unclosed) > 20:
    print(f"  ... and {len(unclosed) - 20} more")
