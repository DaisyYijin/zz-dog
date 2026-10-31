#!/usr/bin/env bash
# ============================================================
# 一键部署 VLESS-Reality 中转节点（在香港 Ubuntu/Debian 服务器上运行）
# 用法:  bash setup.sh
# 可选环境变量:
#   PORT=8443        宿主机监听端口（默认 443）
#   SNI=www.apple.com  伪装目标站点（默认 www.microsoft.com）
#   TAG=HK-Relay     节点备注名
# ============================================================
set -euo pipefail

PORT="${PORT:-443}"
SNI="${SNI:-gateway.icloud.com}"
TAG="${TAG:-HK-Relay}"
cd "$(dirname "$0")"

echo "[1/6] 检查 Docker..."
command -v docker >/dev/null 2>&1 || { echo "错误: 未安装 Docker"; exit 1; }
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "错误: 未找到 docker compose 插件"; exit 1
fi

echo "[2/6] 拉取 xray 镜像..."
docker pull -q ghcr.io/xtls/xray-core:latest

echo "[3/6] 生成 UUID / x25519 密钥对 / shortId..."
UUID="$(docker run --rm --entrypoint xray ghcr.io/xtls/xray-core:latest uuid)"
KEYS="$(docker run --rm --entrypoint xray ghcr.io/xtls/xray-core:latest x25519)"
PRIVATE_KEY="$(printf '%s' "$KEYS" | awk -F': ' '/^Private[Kk]ey:/{print $2}' | tr -d '\r')"
PUBLIC_KEY="$(printf '%s' "$KEYS" | awk -F': ' '/PublicKey\):|^Public [Kk]ey:/{print $2}' | tr -d '\r')"
[ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ] || { echo "错误: 密钥生成失败"; exit 1; }
SHORT_ID="$(openssl rand -hex 8)"

echo "[4/6] 生成服务端配置 config/server.json ..."
sed -e "s|__UUID__|${UUID}|g" \
    -e "s|__SNI__|${SNI}|g" \
    -e "s|__PRIVATE_KEY__|${PRIVATE_KEY}|g" \
    -e "s|__SHORT_ID__|${SHORT_ID}|g" \
    config/server.json.tmpl > config/server.json
chmod 600 config/server.json
printf 'PORT=%s\nTAG=%s\n' "$PORT" "$TAG" > .env

echo "[5/6] 启动容器..."
$COMPOSE up -d
sleep 2
$COMPOSE ps

echo "[6/6] 生成客户端分享链接..."
IP="$(curl -4 -s --max-time 8 https://api.ipify.org || curl -4 -s --max-time 8 https://ip.sb || true)"
[ -n "$IP" ] || IP="服务器公网IP"
LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${TAG}"

echo
echo "================= 部署完成 ================="
echo "客户端导入链接（复制整行）:"
echo "$LINK" | tee client-link.txt
echo "============================================"
echo
if command -v qrencode >/dev/null 2>&1; then
  echo "手机扫码导入:"
  qrencode -t ansiutf8 "$LINK"
else
  echo "提示: 执行 apt-get install -y qrencode 后重跑本脚本，可显示扫码导入二维码。"
fi
echo
echo "别忘了: 云厂商安全组 / ufw 需放行 TCP ${PORT}"
echo "日志: docker logs -f xray-reality"
