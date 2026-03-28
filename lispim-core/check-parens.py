# Check parenthesis balance in gateway.lisp

content = open('C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp', 'r', encoding='utf-8').read()

# Find all top-level forms and track parenthesis depth
depth = 0
max_depth = 0
in_comment = False
in_string = False
prev_char = ''

for i, char in enumerate(content):
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
            if depth > max_depth:
                max_depth = depth
        elif char == ')':
            depth -= 1

    prev_char = char

print(f'Max depth: {max_depth}')
print(f'Final depth: {depth}')
print(f'Expected final depth: 0')
if depth != 0:
    print(f'ERROR: {depth} unclosed parentheses!')
