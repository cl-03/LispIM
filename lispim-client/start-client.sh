#!/bin/bash
# Start LispIM Client REPL
# Usage: ./start-client.sh [host] [port]

HOST=${1:-localhost}
PORT=${2:-3000}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "  LispIM Client REPL"
echo "========================================"
echo ""

sbcl --non-interactive \
     --load quicklisp.lisp \
     --eval "(quicklisp:setup)" \
     --load "$SCRIPT_DIR/repl-client.lisp" \
     --eval "(format t '~%Connecting to ~a:~a...~%' \"$HOST\" \"$PORT\")" \
     --eval "(repl-connect :host \"$HOST\" :port $PORT)"
