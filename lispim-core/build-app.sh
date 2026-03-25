#!/bin/bash
# Build Script for LispIM Backend Desktop Application

APP_NAME="LispIM_backend"
BUILD_DIR="build"
SBCL="/d/SBCL/sbcl.exe"
SBCL_CORE="/d/SBCL/sbcl.core"

echo "================================"
echo "  Building ${APP_NAME}"
echo "================================"

cd /d/Claude/LispIM/lispim-core

# 创建构建目录
mkdir -p "${BUILD_DIR}"

# 清理旧的编译文件
echo "Cleaning old build artifacts..."
rm -f *.fasl src/*.fasl "${BUILD_DIR}/${APP_NAME}"* 2>/dev/null

echo "Compiling executable..."

"${SBCL}" --non-interactive \
  --core "${SBCL_CORE}" \
  --load build-app.lisp \
  --quit

echo "Build complete!"
