content = open('C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp', 'r', encoding='utf-8').read()
lines = content.split('\n')

# Check lines 2140-2192 (api-get-file-handler)
print('Analyzing api-get-file-handler (lines 2140-2192):')
print('=' * 80)
depth = 0
for i in range(2139, min(2192, len(lines))):
    line = lines[i]
    # Count parens (ignoring strings and comments for simplicity)
    in_string = False
    open_count = 0
    close_count = 0
    prev_char = ''
    for char in line:
        if char == '"' and prev_char != chr(92):
            in_string = not in_string
        if not in_string:
            if char == '(':
                open_count += 1
            elif char == ')':
                close_count += 1
        prev_char = char

    net = open_count - close_count
    depth += net
    if open_count > 0 or close_count > 0:
        print(f'{i+1:5d}: depth={depth:3d} (net={net:+d}, +{open_count}/-{close_count}) | {line[:60]}')

print(f'\nFinal depth: {depth} (should be 0)')
