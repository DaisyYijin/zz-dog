# HK-Relay：香港服务器中转访问 Docker Hub / GitHub

手机（国内网络）→ **加密隧道** → 香港服务器 → 直连 Docker Hub / GitHub 等任意网站。

```
┌──────────┐   VLESS+Reality (加密)   ┌──────────────────┐          ┌─────────────┐
│  手机     │ ───────────────────────> │ 香港服务器        │ ───────> │ hub.docker.com│
│ 国内网络  │      TCP 443             │ Ubuntu + Docker  │  直连    │ github.com   │
└──────────┘                          │ [xray-reality]   │          │ ...任意网站   │
                                      └──────────────────┘          └─────────────┘
```

**为什么是代理而不是 Nginx 反代网站**：GitHub / Docker Hub 页面充满绝对链接、登录态和子域名，反代后必然打不开。代理是让手机"借香港服务器的网络身份"上网，访问什么都可以。

**为什么选 VLESS + Reality（Xray）**：无需域名和证书；流量特征伪装成访问正常网站的 HTTPS，稳定抗干扰；单容器部署，资源占用极小；手机客户端成熟。

---

## 一、部署（在香港服务器上，约 2 分钟）

```bash
# 1. 在本地 Windows 上，把整个项目目录传到服务器
scp -r G:/dog root@你的服务器IP:/opt/hk-relay

# 2. SSH 登录服务器后执行
ssh root@你的服务器IP
cd /opt/hk-relay
# 若提示 $'\r': command not found（Windows 换行符问题），先执行：
#   sed -i 's/\r$//' setup.sh
bash setup.sh
```

脚本会自动：生成 UUID 和 x25519 密钥 → 填充配置 → 启动容器 → 打印一个
`vless://...` 分享链接（同时存到 `client-link.txt`）。

**放行端口**：云厂商安全组（阿里云/腾讯云控制台的防火墙规则）放行 **TCP 443**；
如服务器开了 ufw：`ufw allow 443/tcp`。

> 443 被占用时换端口：`PORT=8443 bash setup.sh`（安全组同步放行 8443）。
>
> 伪装目标默认为 `gateway.icloud.com`（已验证 TLS1.3 + h2，Apple 香港边缘节点，
> 国内直连可达）。**不建议**换成 `www.microsoft.com`——新版 xray 会警告该目标
> 过于热门、增加服务器 IP 被墙风险。如需更换（选支持 TLS1.3 的境外站点）：
> `SNI=www.tesla.com bash setup.sh`。

## 二、手机客户端配置

| 系统 | 推荐客户端 | 获取方式 |
|------|-----------|---------|
| Android | **v2rayNG**（免费开源） | GitHub `2dust/v2rayNG` Releases 下载 APK |
| iOS | **Shadowrocket**（付费，需非中区 Apple ID） | App Store |
| iOS 免费替代 | **sing-box** | App Store（导入方式稍复杂） |

导入步骤（以 v2rayNG 为例）：
1. 复制服务器上 `client-link.txt` 里的整行 `vless://...` 链接
2. v2rayNG → 右上角 **＋** → **从剪贴板导入**
3. 点击右下角 **V** 图标连接（首次会请求 VPN 权限，允许）

验证：手机浏览器打开 <https://hub.docker.com> 和 <https://github.com>。

**分流说明**：v2rayNG 默认是"绕过大陆"规则模式——访问国内网站仍走本地网络（不减速），只有受限流量走香港。Shadowrocket 中把"全局路由"设为"配置"即可。

## 三、电脑复用（可选）

Windows/Mac 装 **v2rayN / v2rayNG 桌面版** 或 Clash 系客户端，导入同一个
`vless://` 链接即可，国内电脑也能访问 Docker Hub / GitHub 了。

## 四、日常维护

```bash
cd /opt/hk-relay
docker logs -f xray-reality      # 看日志（应为 Started，无报错）
docker compose pull && docker compose up -d   # 升级 xray 版本
docker compose down             # 停止服务
```

- **连不上排查**：① 服务器能 `ping` 通吗（IP 是否被墙）② 安全组/ufw 放行了吗
  ③ `docker ps` 容器在运行吗 ④ `docker logs xray-reality` 有无报错
- **IP 被墙**（ping 不通但服务器本身正常）：需在云厂商处更换公网 IP 后重跑
  `bash setup.sh` 重新生成链接（或只改链接中的 IP）。
- **添加多台设备**：所有设备导入同一条链接即可，无需改服务端。

## 五、合规与安全须知 ⚠️

- 本方案仅建议用于**访问 Docker Hub、GitHub 等开发资源的个人正当用途**。
  中国大陆对国际联网信道有专门法规（如《计算机信息网络国际联网管理暂行规定》），
  自建跨境链路存在合规风险，请自行评估、知悉后再使用。
- **切勿把链接分享给他人或公开**——节点会被滥用，既拖垮你的服务器也放大法律风险。
- `config/server.json` 与 `client-link.txt` 含密钥，已在 `.gitignore` 中排除，
  不要提交到公开仓库。

## 附录：只拉 Docker 镜像的合规替代（不需要代理）

如果某台国内电脑只需要 `docker pull`，可以在香港服务器再加一个镜像加速服务：

```yaml
# registry-mirror.compose.yml
services:
  mirror:
    image: registry:2
    restart: unless-stopped
    ports: ["5000:5000"]
    environment:
      REGISTRY_PROXY_REMOTEURL: https://registry-1.docker.io
```

国内电脑 `/etc/docker/daemon.json`（Windows 为 Docker Desktop 设置里）添加：
`{"registry-mirrors": ["http://服务器IP:5000"]}` 后重启 Docker。
注意：公开的 mirror 会被扫描滥用，建议用防火墙限制来源 IP。
