# Find parenthesis imbalance in gateway.lisp

content = open('C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp', 'r', encoding='utf-8').read()

# Track depth and find where it goes negative
depth = 0
min_depth = 0
in_comment = False
in_string = False
prev_char = ''
line_num = 1
depth_at_line = {}

for i, char in enumerate(content):
    if char == '\n':
        line_num += 1
        depth_at_line[line_num] = depth

    # Handle comments
    if char == ';' and prev_char != '\\' and not in_string:
        in_comment = True
    if char == '\n' and in_comment:
        in_comment = False

    # Handle strings
    if char == '"' and prev_char != '\\' and not in_comment:
        in_string = not in_string

    # Track depth (only outside comments and strings)
    if not in_comment and not in_string:
        if char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
            if depth < min_depth:
                min_depth = depth
                print(f'Line {line_num}: Depth goes to {depth} (extra closing paren)')

    prev_char = char

print(f'\nFinal depth: {depth}')
print(f'Min depth: {min_depth}')

# Find lines where depth is non-zero at end
print('\nLines where we might have issues (depth should return to 0):')
for line, d in sorted(depth_at_line.items()):
    if d < 0:
        print(f'  Line {line}: depth = {d}')
