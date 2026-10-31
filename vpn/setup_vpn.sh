#!/usr/bin/env bash
# ============================================================
# 一键部署 SoftEther VPN（多用户 L2TP + 网页管理台 + 流量统计）
# 在香港服务器上运行:  cd vpn && bash setup_vpn.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/4] 检查 Docker..."
command -v docker >/dev/null 2>&1 || { echo "错误: 未安装 Docker"; exit 1; }
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "错误: 未找到 docker compose 插件"; exit 1
fi

echo "[2/4] 生成/读取凭据..."
if [ ! -f .env ]; then
  PSK="$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-20)"
  ADMIN_PW="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
  VUSER="vpn$(openssl rand -hex 3)"
  VPASS="$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-16)"
  USERS="${VUSER}:${VPASS}"
  printf 'PSK=%s\nADMIN_PASSWORD=%s\nUSERS=%s\n' "$PSK" "$ADMIN_PW" "$USERS" > .env
  chmod 600 .env
  echo "已生成新凭据并保存到 vpn/.env"
else
  echo "复用已有 vpn/.env（重置凭据: rm vpn/.env 后重跑）"
fi

echo "[3/4] 拉取镜像并启动..."
docker pull siomiz/softethervpn:latest
$COMPOSE up -d
sleep 5
$COMPOSE ps
echo "--- 容器日志（末尾几行）---"
docker logs softether-vpn 2>&1 | tail -5

echo "[4/4] 输出连接与管理信息..."
IP="$(curl -4 -s --max-time 8 https://api.ipify.org || curl -4 -s --max-time 8 https://ip.sb || true)"
[ -n "$IP" ] || IP="服务器公网IP"
PSK="$(sed -n 's/^PSK=//p' .env)"
ADMIN_PW="$(sed -n 's/^ADMIN_PASSWORD=//p' .env)"
VUSER="$(sed -n 's/^USERS=//p' .env | cut -d: -f1)"
cat <<EOF

================= 网页管理台（浏览器打开） ================
  地址   :  https://${IP}:5555
  管理密码:  ${ADMIN_PW}        （选"VPN Server 管理"，密码即此）
  功能   :  新建/删除用户（可留空密码）、查看每用户在线与流量
=============================================================
================= 手机 L2TP 填写（自带 VPN） ================
  服务器地址      :  ${IP}
  IPSec 预共享密钥:  ${PSK}
  用户名          :  ${VUSER}   （初始账号，更多人员在管理台创建）
  密码            :  见 vpn/.env 中 USERS 的对应密码
  Android "IPSec 标识"留空；iOS 类型选 L2TP，"密钥"=预共享密钥
=============================================================
安全组需放行: UDP 500/4500/1701、TCP 5555
EOF
