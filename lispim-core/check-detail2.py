# Detailed parenthesis check for gateway.lisp around api-get-file-handler

content = open('C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp', 'r', encoding='utf-8').read()
lines = content.split('\n')

# Check lines 2140-2195
print('Lines 2140-2195 (api-get-file-handler):')
print('=' * 80)
depth = 0
for i, line in enumerate(lines, 1):
    if 2140 <= i <= 2195:
        line_stripped = line.lstrip()
        # Count parens in this line (ignoring strings and comments)
        in_string = False
        in_comment = False
        open_count = 0
        close_count = 0
        prev_char = ''
        for char in line:
            if char == ';' and prev_char != '\\' and not in_string:
                in_comment = True
            if char == '"' and prev_char != '\\' and not in_comment:
                in_string = not in_string
            if not in_string and not in_comment:
                if char == '(':
                    open_count += 1
                elif char == ')':
                    close_count += 1
            prev_char = char

        net = open_count - close_count
        depth += net
        print(f'{i:5d}: depth={depth:3d} (net={net:+d}, open={open_count}, close={close_count}) | {line[:70]}')
