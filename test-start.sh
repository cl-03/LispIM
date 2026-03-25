#!/bin/bash
# Test script for LispIM

cd "D:/Claude/LispIM"

sbcl --non-interactive \
  --load "lispim-core/lispim-core.asd" \
  --eval "(asdf:make :lispim-core)" \
  --eval "(format t ~%Gateway function exists: ~a~% (fboundp (quote lispim-core:start-gateway)))" \
  --quit 2>&1 | tail -20
