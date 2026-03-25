#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check from line 1586 to end
in_string = False
string_start_line = 0
escape_next = False
open_count = 0
close_count = 0

for i in range(1585, len(lines)):
    line = lines[i]
    j = 0
    while j < len(line):
        c = line[j]
        if escape_next:
            escape_next = False
        elif c == '\\':
            escape_next = True
        elif c == '"':
            in_string = not in_string
            if in_string:
                string_start_line = i + 1
        elif c == '(':
            open_count += 1
        elif c == ')':
            close_count += 1
        j += 1

    if close_count > open_count and not in_string:
        print(f'Line {i+1}: More closes than opens (open={open_count}, close={close_count})')
        print(f'  Content: {line.rstrip()[:80]}')
        break

if in_string:
    print(f'Unclosed string starting at line {string_start_line}')
else:
    print('No unclosed strings')

print(f'Total from line 1586: open={open_count}, close={close_count}, diff={open_count - close_count}')
