#!/usr/bin/env bash
# ============================================================
# 一键部署 L2TP/IPSec VPN（手机系统自带 VPN 直连，零 App）
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

echo "[2/4] 生成/读取 VPN 凭据..."
if [ ! -f .env ]; then
  PSK="$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-20)"
  VUSER="vpn$(openssl rand -hex 3)"
  VPASS="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
  printf 'VPN_IPSEC_PSK=%s\nVPN_USER=%s\nVPN_PASSWORD=%s\n' "$PSK" "$VUSER" "$VPASS" > .env
  chmod 600 .env
  echo "已生成新凭据并保存到 vpn/.env"
else
  echo "复用已有 vpn/.env（如需重置: rm vpn/.env 后重跑）"
fi

echo "[3/4] 拉取镜像并启动..."
docker pull hwdsl2/ipsec-vpn-server:latest
$COMPOSE up -d
sleep 5
$COMPOSE ps
echo "--- 容器日志（末尾几行）---"
docker logs l2tp-vpn 2>&1 | tail -5

echo "[4/4] 手机端配置信息（妥善保存，勿外传）---"
IP="$(curl -4 -s --max-time 8 https://api.ipify.org || curl -4 -s --max-time 8 https://ip.sb || true)"
[ -n "$IP" ] || IP="服务器公网IP"
PSK="$(sed -n 's/^VPN_IPSEC_PSK=//p' .env)"
VUSER="$(sed -n 's/^VPN_USER=//p' .env)"
VPASS="$(sed -n 's/^VPN_PASSWORD=//p' .env)"
cat <<EOF

================= 手机 VPN 填写信息 =================
  服务器地址      :  ${IP}
  IPSec 预共享密钥:  ${PSK}
  用户名          :  ${VUSER}
  密码            :  ${VPASS}
=====================================================
安全组需放行: UDP 500 和 UDP 4500
iOS    : 设置 → 通用 → VPN与设备管理 → 添加VPN配置 → 类型 L2TP
        服务器=${IP}  账户=${VUSER}  密码=${VPASS}  密钥=${PSK}
Android: 设置 → 网络与互联网 → VPN → 添加 → 类型 L2TP/IPSec PSK
        服务器地址=${IP}  IPSec预共享密钥=${PSK}
        用户名=${VUSER}   密码=${VPASS}  （IPSec标识留空）
提示: 连不上时先查安全组 UDP 500/4500 是否放行
EOF
