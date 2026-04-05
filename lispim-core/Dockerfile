# LispIM Core Dockerfile
# Development and production build

FROM debian:bookworm-slim AS base

# Install SBCL and dependencies
RUN apt-get update && apt-get install -y \
    sbcl \
    curl \
    git \
    postgresql-client \
    redis-tools \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Quicklisp (Common Lisp package manager)
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp && \
    sbcl --non-interactive \
         --load quicklisp.lisp \
         --eval "(quicklisp-quickstart:install)" \
         --eval "(ql:add-to-init-file)" \
         --quit && \
    rm quicklisp.lisp

WORKDIR /app

# Copy system definition
COPY lispim-core.asd .

# Create dummy source for dependency installation
RUN mkdir -p src && \
    echo "(in-package :cl)" > src/package.lisp && \
    echo "(in-package :cl)" > src/server.lisp

# Install Quicklisp dependencies
RUN sbcl --non-interactive \
    --load /app/lispim-core.asd \
    --eval "(ql:quickload :lispim-core)" \
    --quit

# Development stage
FROM base AS development

ENV DATABASE_URL=postgresql://localhost:5432/lispim
ENV REDIS_URL=redis://localhost:6379/0
ENV LOG_LEVEL=debug
ENV LISPIM_HOST=0.0.0.0
ENV LISPIM_PORT=3000

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
ENV LISPIM_HOST=0.0.0.0
ENV LISPIM_PORT=3000

# Copy source code
COPY src/ /app/lispim-core/src/
COPY migrations/ /app/lispim-core/migrations/

# Compile all files
RUN sbcl --non-interactive \
    --load /app/lispim-core/lispim-core.asd \
    --eval "(ql:quickload :lispim-core)" \
    --eval "(compile-file \"/app/lispim-core/src/server\")"

EXPOSE 3000 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/healthz || exit 1

CMD ["sbcl", "--non-interactive", "--load", "/app/lispim-core/src/server.lisp"]
