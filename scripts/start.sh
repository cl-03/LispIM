# LispIM Startup Script
#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LISPIM_CORE_DIR="$PROJECT_DIR/lispim-core"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  LispIM Enterprise Startup Script${NC}"
echo -e "${GREEN}========================================${NC}"

# Check dependencies
check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"

    # Check SBCL
    if ! command -v sbcl &> /dev/null; then
        echo -e "${RED}Error: SBCL is not installed${NC}"
        echo "Please install SBCL from http://www.sbcl.org/"
        exit 1
    fi
    echo "  ✓ SBCL: $(sbcl --version | head -1)"

    # Check PostgreSQL
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}Error: PostgreSQL is not installed${NC}"
        exit 1
    fi
    echo "  ✓ PostgreSQL: $(psql --version)"

    # Check Redis
    if ! command -v redis-cli &> /dev/null; then
        echo -e "${RED}Error: Redis is not installed${NC}"
        exit 1
    fi
    echo "  ✓ Redis: $(redis-cli --version)"

    # Check Quicklisp
    if [ ! -f ~/quicklisp/setup.lisp ]; then
        echo -e "${YELLOW}  Installing Quicklisp...${NC}"
        curl -O https://beta.quicklisp.org/quicklisp.lisp
        sbcl --non-interactive \
            --load quicklisp.lisp \
            --eval '(quicklisp-quickstart:install)' \
            --eval '(ql:add-to-init-file)' \
            --quit
        rm quicklisp.lisp
    fi
    echo "  ✓ Quicklisp installed"
}

# Initialize database
init_database() {
    echo -e "${YELLOW}Initializing database...${NC}"

    # Check if database exists
    if psql -U postgres -h localhost -lqt | cut -d \| -f 1 | grep -qw lispim; then
        echo "  Database 'lispim' already exists"
    else
        echo "  Creating database 'lispim'..."
        psql -U postgres -h localhost -c "CREATE DATABASE lispim;"
    fi

    # Run initialization script
    echo "  Running initialization script..."
    psql -U postgres -h localhost -d lispim -f "$SCRIPT_DIR/init-db.sql"

    echo -e "  ${GREEN}Database initialized${NC}"
}

# Start Redis
start_redis() {
    echo -e "${YELLOW}Starting Redis...${NC}"

    if pgrep -x "redis-server" > /dev/null; then
        echo "  Redis is already running"
    else
        redis-server --daemonize yes
        echo -e "  ${GREEN}Redis started${NC}"
    fi
}

# Install Lisp dependencies
install_lisp_deps() {
    echo -e "${YELLOW}Installing Lisp dependencies...${NC}"

    sbcl --non-interactive \
        --load "$LISPIM_CORE_DIR/lispim-core.asd" \
        --eval '(ql:quickload :lispim-core)' \
        --quit

    echo -e "  ${GREEN}Dependencies installed${NC}"
}

# Start LispIM server
start_server() {
    echo -e "${YELLOW}Starting LispIM server...${NC}"

    cd "$LISPIM_CORE_DIR"

    # Set environment variables
    export DATABASE_URL="${DATABASE_URL:-postgresql://localhost:5432/lispim}"
    export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"

    # Start SBCL
    sbcl --non-interactive \
         --load "$LISPIM_CORE_DIR/src/server.lisp" \
         --eval '(lispim-core:start-server)' \
         --eval '(loop while lispim-core:*server-running* do (sleep 1))'
}

# Main
main() {
    case "${1:-start}" in
        init)
            check_dependencies
            init_database
            ;;
        deps)
            check_dependencies
            install_lisp_deps
            ;;
        start)
            check_dependencies
            start_redis
            init_database
            install_lisp_deps
            start_server
            ;;
        dev)
            echo -e "${YELLOW}Starting development mode...${NC}"
            check_dependencies
            start_redis
            cd "$LISPIM_CORE_DIR"
            sbcl --load "$LISPIM_CORE_DIR/lispim-core.asd"
            ;;
        stop)
            echo -e "${YELLOW}Stopping LispIM server...${NC}"
            pkill -f "sbcl.*server" || true
            echo -e "${GREEN}Server stopped${NC}"
            ;;
        *)
            echo "Usage: $0 {init|deps|start|dev|stop}"
            exit 1
            ;;
    esac
}

main "$@"
