#!/bin/bash
# MinIO 初始化脚本
# 创建 LispIM 所需的存储桶

# MinIO 配置
MINIO_ENDPOINT="${MINIO_ENDPOINT:-localhost:9000}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-lispim}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-Clsper03}"

# 等待 MinIO 启动
echo "等待 MinIO 启动..."
sleep 5

# 使用 mc 客户端创建存储桶
echo "创建存储桶：lispim-files"

# 检查 mc 是否安装
if ! command -v mc &> /dev/null; then
    echo "未找到 mc 客户端，请手动创建存储桶："
    echo "1. 访问 http://localhost:9001"
    echo "2. 登录：lispim / Clsper03"
    echo "3. 创建存储桶：lispim-files"
    exit 0
fi

# 配置别名
mc alias set lispim http://$MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# 创建存储桶
mc mb lispim/lispim-files

# 设置公开访问（可选）
# mc policy set download lispim/lispim-files

echo "MinIO 初始化完成！"
