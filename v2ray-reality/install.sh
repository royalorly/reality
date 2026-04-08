#!/bin/bash
set -e

# 三个独立随机端口
REALITY_PORT=$(shuf -i 20000-30000 -n1)
HY2_PORT=$(shuf -i 30001-40000 -n1)
TUIC_PORT=$(shuf -i 40001-50000 -n1)

UUID=$(cat /proc/sys/kernel/random/uuid)
SERVER_IP=$(curl -s ipv4.ip.sb 2>/dev/null || curl -s ifconfig.me)
SUB_PORT=58288
SUB_DIR=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

# 安装依赖
apt update -y
apt install -y wget unzip qrencode curl openssl -y

# 安装 Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成 Reality 密钥
xray x25519 > /tmp/x25519
PRIVATE_KEY=$(sed -n '2p' /tmp/x25519 | awk '{print $3}')
PUBLIC_KEY=$(sed -n '1p' /tmp/x25519 | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

SNI="www.apple.com"

# 随机密码
HY2_PASS=$(openssl rand -hex 8)
TUIC_PASS=$(openssl rand -hex 8)

# ==========================
# Xray Reality
# ==========================
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $REALITY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.apple.com:443",
          "serverNames": ["www.apple.com"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# ==========================
# Hysteria2
# ==========================
bash -c "$(curl -fsSL https://get.hy2.sh/)"

cat > /etc/hysteria/config.yaml << EOF
listen: 0.0.0.0:$HY2_PORT
tls:
  cert: /dev/null
  key: /dev/null
  alpn: [h3]
auth:
  type: password
  password: "$HY2_PASS"
masquerade:
  type: proxy
  proxy:
    url: https://www.apple.com
    rewriteHost: true
EOF

# ==========================
# TUIC
# ==========================
wget -O /usr/local/bin/tuic-server https://github.com/EAimTY/tuic/releases/latest/download/tuic-server-linux-amd64
chmod +x /usr/local/bin/tuic-server

cat > /etc/tuic.json << EOF
{
  "server": "0.0.0.0:$TUIC_PORT",
  "users": [{"uuid": "$UUID", "password": "$TUIC_PASS"}],
  "certificate": "/dev/null",
  "private_key": "/dev/null",
  "alpn": ["h3"],
  "congestion_control": "bbr"
}
EOF

cat > /etc/systemd/system/tuic.service << EOF
[Unit]
Description=TUIC Server
After=network.target

[Service]
ExecStart=/usr/local/bin/tuic-server -c /etc/tuic.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable --now xray
systemctl enable --now hysteria
systemctl enable --now tuic

# ==========================
# 输出节点 + 二维码
# ==========================
clear
echo "========================================"
echo "          三合一节点安装完成"
echo "     Reality + Hysteria2 + TUIC"
echo "========================================"
echo

# 1 Reality
echo "【1】VLESS Reality"
LINK1="vless://$UUID@$SERVER_IP:$REALITY_PORT?security=reality&sni=$SNI&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=xtls-rprx-vision#JP_Reality"
echo "$LINK1"
echo
qrencode -t ansiutf8 "$LINK1"
echo

# 2 Hysteria2
echo "【2】Hysteria2"
LINK2="hysteria2://$HY2_PASS@$SERVER_IP:$HY2_PORT?insecure=1&sni=$SNI&alpn=h3#JP_Hysteria2"
echo "$LINK2"
echo
qrencode -t ansiutf8 "$LINK2"
echo

# 3 TUIC
echo "【3】TUIC"
LINK3="tuic://$UUID:$TUIC_PASS@$SERVER_IP:$TUIC_PORT?insecure=1&sni=$SNI&alpn=h3#JP_TUIC"
echo "$LINK3"
echo
qrencode -t ansiutf8 "$LINK3"
echo

# 订阅地址（YAML 格式通用）
echo "【订阅地址】"
echo "http://$SERVER_IP:$SUB_PORT/$SUB_DIR"
echo "========================================"
echo "安全组放行：TCP 20000-50000 / UDP 20000-50000"
echo "========================================"
