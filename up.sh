#!/bin/bash

# ==============================================================================
# 脚本功能：Binom_自定义 By：bycine@gmail.com QQ:133205
# ==============================================================================

set -euo pipefail

BINOM_DIR="/root/binom"
ENV_FILE="${BINOM_DIR}/.env"
REGISTRY="gcr.io/pr-binom"
BAK_DIR="/root/path/bak"

DOWNLOAD_DIR="/tmp/binom_download"
SRC_BINOM_GO="${DOWNLOAD_DIR}/path/binom-go"
SRC_PROTECT="${DOWNLOAD_DIR}/path/protect"

# 询问版本号
echo "=================================================="
echo "🚀 请输入补丁版本号" 
echo "✅ 已支持 #2.34.00 #2.33.03" 
echo "=================================================="
read -p "版本号: " VERSION
if [ -z "$VERSION" ]; then
    echo "❌ 版本号不能为空"
    exit 1
fi
echo "✅ 使用版本: $VERSION"

BASE_URL="https://data.xxok.ccwu.cc/${VERSION}"
URLS=(
    "${BASE_URL}/path.tar.gz.part.00"
    "${BASE_URL}/path.tar.gz.part.01"
    "${BASE_URL}/path.tar.gz.part.02"
)

show_progress() {
    local duration=$1
    local label=$2
    local col=50
    echo -n "$label "
    for ((i=1; i<=col; i++)); do
        echo -n "."
        sleep "$(echo "scale=3; $duration / $col" | bc)"
    done
    echo " [OK]"
}

echo "=================================================="
echo "🚀 开始执行 Binom 自动化部署与备份脚本..."
echo "=================================================="

echo "📥 [1/8] 正在边缘节点下载分卷文件..."
rm -rf "$DOWNLOAD_DIR" && mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

for url in "${URLS[@]}"; do
    filename=$(basename "$url")
    echo "--------------------------------------------------"
    echo "📥 正在下载: $filename"
    wget -c --show-progress -q "$url"
done
echo "--------------------------------------------------"

echo "🔗 [2/8] 正在处理压缩包..."
cat path.tar.gz.part.* > path.tar.gz
tar -zxf path.tar.gz
chmod +x "$SRC_BINOM_GO" "$SRC_PROTECT"
show_progress 1.5 "-> 正在解压分卷并赋予执行权限"

echo "🔍 [3/8] 正在读取当前运行的容器版本..."
DEFAULT_TD_TAG="v1.41.0"
DEFAULT_PROTECT_TAG="v1.18.2"

if docker inspect binom_traffic_distribution &>/dev/null; then
    TD_TAG=$(docker inspect --format='{{index (split .Config.Image ":") 1}}' binom_traffic_distribution)
    echo "💡 检测到当前 traffic-distribution 版本为: $TD_TAG"
else
    TD_TAG=$DEFAULT_TD_TAG
    echo "⚠️ 未检测到运行中的 traffic-distribution，使用默认版本: $TD_TAG"
fi

if docker inspect binom_protect &>/dev/null; then
    PROTECT_TAG=$(docker inspect --format='{{index (split .Config.Image ":") 1}}' binom_protect)
    echo "💡 检测到当前 protect 版本为: $PROTECT_TAG"
else
    PROTECT_TAG=$DEFAULT_PROTECT_TAG
    echo "⚠️ 未检测到运行中的 protect，使用默认版本: $PROTECT_TAG"
fi


echo "💾 [4/8] 正在对当前运行环境执行安全备份..."
rm -rf "$BAK_DIR" && mkdir -p "$BAK_DIR"

if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "$BAK_DIR/binom.env"
fi

if docker ps --format '{{.Names}}' | grep -q '^binom_traffic_distribution$'; then
    docker cp binom_traffic_distribution:/binom-go "$BAK_DIR/binom-go" || echo "⚠️ 容器内未找到 /binom-go"
    docker cp binom_traffic_distribution:/config.yaml "$BAK_DIR/config.yaml" || echo "⚠️ 容器内未找到 /config.yaml"
fi

if docker ps --format '{{.Names}}' | grep -q '^binom_protect$'; then
    docker cp binom_protect:/app/protect "$BAK_DIR/protect" || echo "⚠️ 容器内未找到 /app/protect"
fi
show_progress 2.0 "-> 正在导出容器内关键数据至 $BAK_DIR"


echo "⚙️ [5/8] 正在检查解压后的文件和系统环境..."
if [ ! -f "$SRC_BINOM_GO" ] || [ ! -f "$SRC_PROTECT" ] || [ ! -f "$ENV_FILE" ]; then
    echo "❌ 错误: 关键文件缺失，无法继续覆盖，请检查环境！" && exit 1
fi
show_progress 0.5 "-> 环境校验通过"

echo "🧹 [6/8] 正在清理旧容器并修改 .env 配置..."
docker rm -f binom_traffic_distribution binom_protect 2>/dev/null || true

sudo sed -i 's|BINOM_LICENSE_HOST=license.binom.network|BINOM_LICENSE_HOST=lic.xxok.ccwu.cc|' "$ENV_FILE"
# sudo sed -i '/^ADDRESS=/d;$a ADDRESS=https://lic.xxok.ccwu.cc' "$ENV_FILE"
show_progress 1.0 "-> 旧容器已销毁，.env 配置授权修正"

echo "🐳 [7/8] 正在保持原版本重新创建容器..."
cd "$BINOM_DIR"
REGISTRY="$REGISTRY" TD_TAG="$TD_TAG" PROTECT_TAG="$PROTECT_TAG" docker-compose up -d traffic-distribution protect > /dev/null
show_progress 3.0 "-> Docker Compose 正在初始化新容器环境"

echo "📂 [8/8] 正在安全替换容器内二进制文件..."

docker stop binom_traffic_distribution > /dev/null
docker cp "$SRC_BINOM_GO" binom_traffic_distribution:/binom-go
docker start binom_traffic_distribution > /dev/null
show_progress 1.5 "-> 已完成 binom_traffic_distribution 的冷替换与注入"

docker stop binom_protect > /dev/null
docker cp "$SRC_PROTECT" binom_protect:/app/protect
docker start binom_protect > /dev/null
show_progress 1.5 "-> 已完成 binom_protect 的冷替换与注入"


rm -rf "$DOWNLOAD_DIR"

echo "=================================================="
echo "🎉 恭喜！环境备份/root/path/bak"
echo "域名10年，部署在cloudflare workers"
echo "解锁完成-访问https://lic.xxok.ccwu.cc/"
echo "=================================================="