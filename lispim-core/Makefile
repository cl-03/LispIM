# LispIM Core Makefile
# Build, test, and development automation

# Configuration
SBCL ?= sbcl
ASDF_SYSTEM := lispim-core
TEST_SYSTEM := lispim-core/test

# Colors for output
BLUE := \033[34m
GREEN := \033[32m
RED := \033[31m
YELLOW := \033[33m
NC := \033[0m

.PHONY: all build test clean dev help lint format

# Default target
all: build

# Build the system
build:
	@echo "$(BLUE)Building $(ASDF_SYSTEM)...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :$(ASDF_SYSTEM))" \
		--quit
	@echo "$(GREEN)Build successful!$(NC)"

# Run tests
test:
	@echo "$(BLUE)Running tests...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :$(TEST_SYSTEM))" \
		--eval "(asdf:test-system :$(ASDF_SYSTEM))" \
		--quit
	@echo "$(GREEN)All tests passed!$(NC)"

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@find . -name "*.fasl" -type f -delete
	@find . -name "*.lib" -type f -delete
	@find . -name "*.sl" -type f -delete
	@find . -name "*.core" -type f -delete
	@echo "$(GREEN)Clean complete!$(NC)"

# Development mode - load with REPL
dev:
	@echo "$(BLUE)Starting development REPL...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :$(ASDF_SYSTEM))" \
		--eval "(in-package :lispim-core)"

# Start server
start:
	@echo "$(BLUE)Starting LispIM server...$(NC)"
	@$(SBCL) --non-interactive \
		--load lispim-backend-app.lisp \
		--eval "(lispim-core:start-server)" \
		--quit

# Run linter (check for common issues)
lint:
	@echo "$(BLUE)Running linter...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :$(ASDF_SYSTEM))" \
		--eval "(progn (require 'sb-introspect) (sb-introspect:find-definition-source (find-symbol 'START-SERVER :lispim-core)))" \
		--quit
	@echo "$(GREEN)Lint complete!$(NC)"

# Format code (requires cl-format or similar)
format:
	@echo "$(YELLOW)Formatting code...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :lisp-format)" \
		--eval "(lisp-format:format-system :$(ASDF_SYSTEM))" \
		--quit
	@echo "$(GREEN)Format complete!$(NC)"

# Generate documentation
docs:
	@echo "$(BLUE)Generating documentation...$(NC)"
	@echo "Documentation generation not yet implemented"
	@echo "$(YELLOW)Consider adding MeroX or Codex for auto-docs$(NC)"

# Run benchmarks
bench:
	@echo "$(BLUE)Running benchmarks...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :$(ASDF_SYSTEM))" \
		--eval "(lispim-core::run-benchmarks)" \
		--quit

# Check dependencies
deps:
	@echo "$(BLUE)Checking dependencies...$(NC)"
	@$(SBCL) --non-interactive \
		--eval "(ql:quickload :$(ASDF_SYSTEM))" \
		--eval "(format t \"~%Loaded systems:~%\")" \
		--eval "(dolist (sys (asdf:loaded-systems) (format t \"  ~a~%\" (asdf:system-name sys))))" \
		--quit

# Help
help:
	@echo "$(BLUE)LispIM Core Makefile$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)build$(NC)   - Build the system"
	@echo "  $(GREEN)test$(NC)    - Run all tests"
	@echo "  $(GREEN)clean$(NC)   - Remove build artifacts"
	@echo "  $(GREEN)dev$(NC)     - Load system in REPL"
	@echo "  $(GREEN)start$(NC)   - Start the server"
	@echo "  $(GREEN)lint$(NC)    - Run linter"
	@echo "  $(GREEN)format$(NC)  - Format code"
	@echo "  $(GREEN)docs$(NC)    - Generate documentation"
	@echo "  $(GREEN)bench$(NC)   - Run benchmarks"
	@echo "  $(GREEN)deps$(NC)    - Check dependencies"
	@echo "  $(GREEN)help$(NC)    - Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  SBCL       - SBCL binary (default: sbcl)"
