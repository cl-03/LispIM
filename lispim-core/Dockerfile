# LispIM Core Dockerfile
# Development and production build

FROM debian:bookworm-slim AS base

# Install SBCL and dependencies
RUN apt-get update && apt-get install -y \
    sbcl \
    curl \
    git \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Roswell (Common Lisp implementation manager)
RUN curl -L https://raw.githubusercontent.com/roswell/roswell/release/scripts/install.roswell.sh | sh

WORKDIR /app

# Copy system definition
COPY lispim-core.asd .

# Create dummy source for dependency installation
RUN mkdir -p src && \
    echo "(in-package :cl)" > src/package.lisp && \
    echo "(in-package :cl)" > src/server.lisp

# Install Quicklisp dependencies
RUN sbcl --non-interactive \
    --eval '(ql:quickload :ql-registered-systems)' \
    --eval '(setf ql:*quicklisp-home* "/root/quicklisp")' \
    --load /app/lispim-core.asd || true

# Development stage
FROM base AS development

ENV DATABASE_URL=postgresql://localhost:5432/lispim
ENV REDIS_URL=redis://localhost:6379/0
ENV LOG_LEVEL=debug

VOLUME ["/app/lispim-core"]
VOLUME ["/root/.sbcl"]

EXPOSE 3000 9000

ENTRYPOINT ["sbcl"]
CMD ["--non-interactive", "--load", "/app/lispim-core/src/server.lisp"]

# Production stage
FROM base AS production

ENV DATABASE_URL=postgresql://postgres:5432/lispim
ENV REDIS_URL=redis://redis:6379/0
ENV LOG_LEVEL=info

# Copy source code
COPY src/ /app/lispim-core/src/

# Compile all files
RUN sbcl --non-interactive \
    --load /app/lispim-core/lispim-core.asd \
    --eval '(ql:quickload :lispim-core)' \
    --eval '(compile-file "/app/lispim-core/src/server")'

EXPOSE 3000 9000

CMD ["sbcl", "--non-interactive", "--load", "/app/lispim-core/src/server.lisp"]
