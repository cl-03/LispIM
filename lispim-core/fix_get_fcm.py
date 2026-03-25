#!/usr/bin/env python3
"""Check and fix api-get-fcm-tokens-handler function"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    content = f.read()
    lines = f.readlines()

# Find the function end (end of file)
start_line = 2263  # 0-indexed

# Check paren balance
open_count = 0
close_count = 0
depth = 0

for i in range(start_line, len(lines)):
    line = lines[i]
    line_open = line.count('(')
    line_close = line.count(')')
    open_count += line_open
    close_count += line_close
    depth += line_open - line_close

print(f"Function spans lines {start_line+1} to {len(lines)}")
print(f"Total: open={open_count}, close={close_count}, diff={open_count - close_count}")
print(f"Final depth: {depth} (should be 0 for complete function)")

if depth > 0:
    print(f"Need {depth} more closing parens")
    # Add closing parens at the end
    old = b';;; End of gateway.lisp'
    new = b')))))))\r\n\r\n;;; End of gateway.lisp'
    if old in content.encode('utf-8'):
        content = content.replace(';;; End of gateway.lisp', '))))))\r\n\r\n;;; End of gateway.lisp')
        print(f'Added 6 closing parens at end of file')
    else:
        print('Pattern not found')

    with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'w', encoding='utf-8') as f:
        f.write(content)
else:
    print("Function is balanced")
