#!/usr/bin/env python3
with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'rb') as f:
    content = f.read().decode('utf-8')

# More thorough check - track quote state across lines
lines = content.split('\n')
in_string = False
string_start_line = 0
escape_next = False

for i, line in enumerate(lines, 1):
    j = 0
    while j < len(line):
        c = line[j]
        if escape_next:
            escape_next = False
        elif c == chr(92):  # backslash
            escape_next = True
        elif c == '"':
            in_string = not in_string
            if in_string:
                string_start_line = i
        j += 1

if in_string:
    print(f'Unclosed string starting at line {string_start_line}')
    # Show context
    for k in range(max(0, string_start_line-2), min(len(lines), string_start_line+5)):
        print(f'{k+1}: {lines[k][:100]}')
else:
    print('All strings are properly closed')

print(f'Total lines: {len(lines)}')
