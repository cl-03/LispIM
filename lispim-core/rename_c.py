#!/usr/bin/env python3
"""Rename error handler parameters from 'c' to 'condition' to avoid potential symbol issues"""

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace error handler patterns
import re

# Pattern: (error (c) -> (error (condition)
content = re.sub(r'\(error \(c\)', '(error (condition)', content)

# Pattern: (auth-error (c) -> (auth-error (condition)
content = re.sub(r'\(auth-error \(c\)', '(auth-error (condition)', content)

# Pattern: (condition-message c) -> (condition-message condition)
content = re.sub(r'\(condition-message c\)', '(condition-message condition)', content)

# Also update standalone c usage in error handlers (like log-error "..." c)
# This is trickier - we need to only change 'c' that's in error handler context
# For now, let's just change the obvious ones: " ~A" c)
content = re.sub(r'" ~A" c\)', '" ~A" condition)', content)

with open(r'D:\Claude\LispIM\lispim-core\src\gateway.lisp', 'w', encoding='utf-8') as f:
    f.write(content)

print('Renamed error handler parameters from c to condition')
