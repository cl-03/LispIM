content = open('C:/Users/Administrator/quicklisp/local-projects/lispim-core/src/gateway.lisp', 'r', encoding='utf-8').read()

# Check for unclosed strings
in_string = False
string_start = -1
in_comment = False
prev_char = ''
bslash = chr(92)

for i, char in enumerate(content):
    if char == '\n':
        in_comment = False

    if char == ';' and prev_char != bslash and not in_string:
        in_comment = True

    if char == '"' and prev_char != bslash and not in_comment:
        if in_string:
            in_string = False
        else:
            in_string = True
            string_start = i

    prev_char = char

if in_string:
    # Find line number
    line_num = content[:string_start].count('\n') + 1
    print(f'UNCLOSED STRING starting at line {line_num}')
    # Show context
    ctx_start = max(0, string_start - 50)
    ctx_end = min(len(content), string_start + 100)
    print(f'Context: ...{content[ctx_start:ctx_end]}...')
else:
    print('No unclosed strings found')

# Check for backslash issues
backslash_count = content.count('\\')
print(f'Backslash count: {backslash_count}')
