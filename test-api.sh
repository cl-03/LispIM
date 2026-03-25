#!/bin/bash
# LispIM API 测试脚本
# 测试新的 /api/v1/ 端点

API_BASE="http://localhost:3000/api/v1"
PASS=0
FAIL=0

echo "========================================"
echo "LispIM API v1 测试"
echo "========================================"
echo ""

# 检查服务器是否运行
check_server() {
    echo "检查服务器状态..."
    curl -s "${API_BASE%/*}/healthz" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 服务器未运行在 http://localhost:3000"
        echo "请先启动服务器：./scripts/start.sh start"
        exit 1
    fi
    echo "✓ 服务器正在运行"
    echo ""
}

# 测试健康检查
test_health() {
    echo "测试 1: 健康检查 (GET /healthz)"
    response=$(curl -s -w "\n%{http_code}" "${API_BASE%/*}/healthz")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    if [ "$code" = "200" ] && [ "$body" = "OK" ]; then
        echo "✓ 通过 - HTTP $code: $body"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code: $body"
        ((FAIL++))
    fi
    echo ""
}

# 测试就绪检查
test_ready() {
    echo "测试 2: 就绪检查 (GET /readyz)"
    response=$(curl -s -w "\n%{http_code}" "${API_BASE%/*}/readyz")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    if [ "$code" = "200" ]; then
        echo "✓ 通过 - HTTP $code: $body"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code: $body"
        ((FAIL++))
    fi
    echo ""
}

# 测试登录 API
test_login() {
    echo "测试 3: 登录 API (POST /api/v1/auth/login)"
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"username":"testuser","password":"testpass"}' \
        "${API_BASE}/auth/login")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    echo "响应: $body"
    if [ "$code" = "200" ] || [ "$code" = "401" ]; then
        echo "✓ 通过 - HTTP $code (期望的响应)"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code"
        ((FAIL++))
    fi
    echo ""
}

# 测试注册 API
test_register() {
    echo "测试 4: 注册 API (POST /api/v1/auth/register)"
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"method":"username","username":"newuser_'$(date +%s)'","password":"newpass123","email":"test@example.com"}' \
        "${API_BASE}/auth/register")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    echo "响应: $body"
    if [ "$code" = "200" ] || [ "$code" = "400" ]; then
        echo "✓ 通过 - HTTP $code (期望的响应)"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code"
        ((FAIL++))
    fi
    echo ""
}

# 测试发送验证码 API
test_send_code() {
    echo "测试 5: 发送验证码 API (POST /api/v1/auth/send-code)"
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"method":"email","value":"test@example.com"}' \
        "${API_BASE}/auth/send-code")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    echo "响应: $body"
    if [ "$code" = "200" ] || [ "$code" = "429" ]; then
        echo "✓ 通过 - HTTP $code (期望的响应)"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code"
        ((FAIL++))
    fi
    echo ""
}

# 测试未授权访问
test_unauthorized() {
    echo "测试 6: 未授权访问 (GET /api/v1/chat/conversations)"
    response=$(curl -s -w "\n%{http_code}" \
        "${API_BASE}/chat/conversations")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    echo "响应: $body"
    if [ "$code" = "401" ]; then
        echo "✓ 通过 - HTTP $code (需要认证)"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code (期望 401)"
        ((FAIL++))
    fi
    echo ""
}

# 测试 404 端点
test_not_found() {
    echo "测试 7: 404 Not Found (GET /api/v1/nonexistent)"
    response=$(curl -s -w "\n%{http_code}" \
        "${API_BASE}/nonexistent")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    echo "响应: $body"
    if [ "$code" = "404" ]; then
        echo "✓ 通过 - HTTP $code"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code (期望 404)"
        ((FAIL++))
    fi
    echo ""
}

# 测试 405 Method Not Allowed
test_method_not_allowed() {
    echo "测试 8: 405 Method Not Allowed (PUT /api/v1/auth/login)"
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Content-Type: application/json" \
        -d '{"username":"test","password":"test"}' \
        "${API_BASE}/auth/login")
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)

    echo "响应: $body"
    if [ "$code" = "405" ]; then
        echo "✓ 通过 - HTTP $code"
        ((PASS++))
    else
        echo "❌ 失败 - HTTP $code (期望 405)"
        ((FAIL++))
    fi
    echo ""
}

# 主测试流程
run_tests() {
    check_server
    test_health
    test_ready
    test_login
    test_register
    test_send_code
    test_unauthorized
    test_not_found
    test_method_not_allowed

    echo "========================================"
    echo "测试结果汇总"
    echo "========================================"
    echo "通过：$PASS"
    echo "失败：$FAIL"
    echo "总计：$((PASS + FAIL))"
    echo ""

    if [ $FAIL -eq 0 ]; then
        echo "🎉 全部测试通过!"
        exit 0
    else
        echo "⚠️  有测试失败"
        exit 1
    fi
}

run_tests
