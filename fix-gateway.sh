#!/bin/bash
# Fix return-from issues in gateway.lisp

# The issue is that return-from is used with function names created by define-easy-handler
# These are not lexical tags, so SBCL compilation fails

# We need to restructure the code to use if/else instead of unless/return-from pattern

cd "D:/Claude/LispIM/lispim-core/src"

# Backup original file
cp gateway.lisp gateway.lisp.bak

# Use a more sophisticated approach - rewrite the file using sed
# This is a complex task, so let's use a Python script instead

python3 fix-gateway.py

echo "Fix complete"
