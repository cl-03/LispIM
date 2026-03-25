#!/usr/bin/env python3
import re

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove comments
content_no_comments = re.sub(r';.*', '', content)
# Remove strings (simple approach)
content_no_strings = re.sub(r'"[^"\\\\]*(\\\\.[^"\\\\]*)*"', '', content_no_comments)

# Count total parens
open_parens = content_no_strings.count('(')
close_parens = content_no_strings.count(')')
print(f'Total open: {open_parens}, close: {close_parens}, diff: {open_parens - close_parens}')

# Count keywords
defuns = content_no_strings.count('(defun')
lets = content_no_strings.count('(let')
let_stars = content_no_strings.count('(let*')
handler_cases = content_no_strings.count('(handler-case')
prognos = content_no_strings.count('(progn')

print(f'defun: {defuns}')
print(f'let: {lets}')
print(f'let*: {let_stars}')
print(f'handler-case: {handler_cases}')
print(f'progn: {prognos}')
