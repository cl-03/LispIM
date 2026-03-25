#!/usr/bin/env python3
"""Find unclosed structures in the file"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Track paren depth at each line
depth_at_line = []
current_depth = 0
in_string = False
escape_next = False

for i, line in enumerate(lines):
    start_depth = current_depth
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

    depth_at_line.append((start_depth, current_depth))

    # Check for negative depth (more closes than opens)
    if current_depth < 0:
        print(f"Line {i+1}: Negative depth ({current_depth})")
        print(f"  Content: {line.rstrip()[:80]}")

# Find defuns and check if they're closed
for i, line in enumerate(lines):
    if '(defun ' in line:
        # Find the depth change for this defun
        start_d, end_d = depth_at_line[i]
        # A defun should add 1 to depth and eventually return to start_d
        func_name = line.split('(defun ')[1].split()[0] if '(defun ' in line else 'unknown'
        print(f"Line {i+1}: defun {func_name} - depth {start_d} -> {end_d}")

print(f"\nFinal depth: {current_depth}")
print(f"Expected: 0 (all structures closed)")
