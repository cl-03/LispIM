# LispIM Enterprise

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Common Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL%202.5.8-yellow.svg)](https://common-lisp.net/)
[![Status](https://img.shields.io/badge/status-alpha-orange.svg)]()

Cloud Native, AI Native, Privacy First Instant Messaging Platform built with Common Lisp.

## Features

- **Real-time Communication** - WebSocket-based messaging with automatic reconnection
- **End-to-End Encryption** - Military-grade E2EE for privacy
- **AI Integration** - OpenClaw AI for intelligent assistance
- **Horizontal Scalability** - Redis-backed session management
- **Modern Architecture** - Cloud-native design with microservices support

## Quick Start

### Prerequisites

- SBCL 2.5.8 or later
- Quicklisp
- PostgreSQL 14+
- Redis 6+

### Installation

```lisp
;; Load with Quicklisp
(ql:quickload :lispim-core)

;; Start the server
(lispim-core:start-server)
```

### Configuration

Environment variables:

```bash
export LISPIM_HOST=0.0.0.0
export LISPIM_PORT=4321
export DATABASE_URL=postgresql://lispim:password@localhost:5432/lispim
export REDIS_URL=redis://localhost:6379/0
export LOG_LEVEL=info
```

### Running Tests

```lisp
(asdf:test-system :lispim-core)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     LispIM Server                            │
├─────────────────────────────────────────────────────────────┤
│  Gateway Layer    │  WebSocket Server + Connection Manager  │
│  ─────────────    │  ─────────────────────────────────────  │
│  Auth Layer       │  JWT + Session Management               │
│  ─────────────    │  ─────────────────────────────────────  │
│  Chat Layer       │  Message Routing + History              │
│  ─────────────    │  ─────────────────────────────────────  │
│  E2EE Layer       │  Encryption/Decryption                  │
│  ─────────────    │  ─────────────────────────────────────  │
│  Storage Layer    │  PostgreSQL + Redis                     │
│  ─────────────    │  ─────────────────────────────────────  │
│  AI Layer         │  OpenClaw Adapter                       │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
lispim-core/
├── src/
│   ├── package.lisp      ; Package definitions
│   ├── conditions.lisp   ; Condition system
│   ├── utils.lisp        ; Utility functions
│   ├── snowflake.lisp    ; Snowflake ID generator
│   ├── auth.lisp         ; Authentication
│   ├── gateway.lisp      ; WebSocket gateway
│   ├── chat.lisp         ; Chat logic
│   ├── e2ee.lisp         ; End-to-end encryption
│   ├── storage.lisp      ; Database/Redis layer
│   ├── oc-adapter.lisp   ; OpenClaw AI adapter
│   ├── observability.lisp; Monitoring & logging
│   └── server.lisp       ; Main entry point
├── tests/
│   └── ...               ; Test suite
├── lispim-core.asd       ; System definition
└── README.md
```

## API Reference

### Server Lifecycle

```lisp
;; Start server
(lispim-core:start-server)

;; Stop server
(lispim-core:stop-server)

;; Restart server
(lispim-core:restart-server)
```

### Authentication

```lisp
;; Register user
(lispim-core:register-user "username" "password")

;; Authenticate
(lispim-core:authenticate "username" "password")
```

### Messaging

```lisp
;; Send message
(lispim-core:send-message user-id conversation-id content)

;; Get history
(lispim-core:get-history conversation-id :limit 50)
```

## Development

### Running in REPL

```lisp
(ql:quickload :lispim-core)
(in-package :lispim-core)
(repl-start)
```

### Building

```bash
sbcl --load lispim-backend-app.lisp \
     --eval "(asdf:make :lispim-core/backend-app)" \
     --quit
```

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## Acknowledgments

- [Quicklisp](https://www.quicklisp.org/) - Common Lisp library manager
- [Hunchentoot](https://github.com/edicl/hunchentoot) - HTTP server
- [Postmodern](https://github.com/marijnh/Postmodern) - PostgreSQL library
- [Bordeaux Threads](https://gitlab.common-lisp.net/bordeaux-threads/bordeaux-threads) - Threading library
