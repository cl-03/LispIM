#!/bin/bash
# start-auto-login.sh - Start LispIM Client with Auto Login (Linux/macOS)
#
# Usage: ./start-auto-login.sh [username] [password] [host] [port]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
USERNAME=${1:-admin}
PASSWORD=${2:-password}
HOST=${3:-localhost}
PORT=${4:-3000}

echo "========================================"
echo "  LispIM Auto-Login Client (Linux/macOS)"
echo "========================================"
echo ""
echo "Server: $HOST:$PORT"
echo "User: $USERNAME"
echo ""

# Check if SBCL is installed
if ! command -v sbcl &> /dev/null; then
    echo "ERROR: SBCL is not installed."
    echo "Install SBCL first:"
    echo "  - Ubuntu/Debian: sudo apt-get install sbcl"
    echo "  - macOS: brew install sbcl"
    echo "  - Arch: sudo pacman -S sbcl"
    exit 1
fi

# Run SBCL with auto-login
eval sbcl --non-interactive \
     --load "$SCRIPT_DIR/quicklisp.lisp" \
     --eval "(quicklisp:setup)" \
     --load "$SCRIPT_DIR/auto-login-client.lisp" \
     --eval "(setf *username* \"$USERNAME\")" \
     --eval "(setf *password* \"$PASSWORD\")" \
     --eval "(setf *server-host* \"$HOST\")" \
     --eval "(setf *server-port* $PORT)" \
     --eval "(auto-connect-and-login)"
