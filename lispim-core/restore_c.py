#!/usr/bin/env python3
"""Restore error handler parameters from 'condition' back to 'c'"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    content = f.read()

import re

# Pattern: (error (condition) -> (error (c)
content = re.sub(r'\(error \(condition\)', '(error (c)', content)

# Pattern: (auth-error (condition) -> (auth-error (c)
content = re.sub(r'\(auth-error \(condition\)', '(auth-error (c)', content)

# Pattern: (condition-message condition) -> (condition-message c)
content = re.sub(r'\(condition-message condition\)', '(condition-message c)', content)

# Also revert: " ~A" condition) -> " ~A" c)
content = re.sub(r'" ~A" condition\)', '" ~A" c)', content)

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'w', encoding='utf-8') as f:
    f.write(content)

print('Restored error handler parameters from condition to c')
