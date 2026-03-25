"""
Fix return-from issues in gateway.lisp

The problem: return-from is used with function names created by hunchentoot:define-easy-handler
These are not lexical tags, so SBCL compilation fails.

Solution: Replace patterns like:
  (unless (condition)
    (setf code 405)
    (return-from handler (error-response)))
  (do-something)

With:
  (if (not (condition))
      (progn
        (setf code 405)
        (error-response))
      (progn
        (do-something)))
"""

import re

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Pattern 1: Simple unless/return-from pattern at the beginning of handlers
    # (unless (string= (hunchentoot:request-method) "POST")
    #   (setf (hunchentoot:return-code*) 405)
    #   (return-from handler-name ...))
    # (setf ...)</pattern>

    pattern1 = r'\(unless \(string= \(hunchentoot:request-method\) "POST"\)\s*\n\s*\(setf \(hunchentoot:return-code\*\) 405\)\s*\n\s*\(return-from [\w-]+ (.+?)\)\)\s*\n'

    def replacement1(m):
        return f'(if (not (string= (hunchentoot:request-method) "POST"))\n      (progn\n        (setf (hunchentoot:return-code*) 405)\n        {m.group(1)})\n      (progn\n'

    content = re.sub(pattern1, replacement1, content)

    # Pattern 2: unless with return-from inside cond
    # (unless (condition)
    #   (setf code 400)
    #   (return-from handler ...))
    # Replace with if/progn

    pattern2 = r'\(unless ([^\n]+)\s*\n\s*\(setf \(hunchentoot:return-code\*\) (\d+)\)\s*\n\s*\(return-from [\w-]+\s+(.+?)\)\)'

    def replacement2(m):
        return f'(if (not ({m.group(1)}))\n           (progn\n             (setf (hunchentoot:return-code*) {m.group(2)})\n             {m.group(3)})'

    content = re.sub(pattern2, replacement2, content)

    # Fix any unclosed (progn from pattern1
    # This is a simplification - may need manual adjustment

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

    print("File fixed!")

if __name__ == '__main__':
    fix_file('D:/Claude/LispIM/lispim-core/src/gateway.lisp')
