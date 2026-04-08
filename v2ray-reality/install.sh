#!/bin/bash

# Xray Reality 安全纯净版 | 含SNI选择 + 扫码 + YAML订阅
# fork自 nbw-dev 清理后门 | royalorly
# 协议：VLESS + reality + xtls-rprx-vision + UDP 正常

set -e

echo "============================================"
echo " Xray Reality 安装脚本 (无后门 + SNI选择)"
echo " 仓库：https://github.com/royalorly/scripts"
echo "============================================"

if [ "$EUID" -ne 0 ]; then
    echo "请用 root 运行"
    exit 1
fi

# 安装依赖
apt update -y
apt install -y curl wget unzip jq openssl qrencode

# 安装官方 Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成基础参数
UUID=$(cat /proc/sys/kernel/random/uuid)
PORT=$(shuf -i 20000-50000 -n1)
IP=$(curl -s --ipv4 ipv4.ip.sb)
KEYPAIR=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/Private key:/{print $3}')
PUBLIC_KEY=$(echo "$KEYPAIR" | awk '/Public key:/{print $3}')
SHORT_ID=$(openssl rand -hex 8)
YAML_PORT=58288

# ==========================================
# SNI 选择菜单
# ==========================================
echo
echo "请选择 SNI（推荐自动测速选最优）："
echo "1) www.google.com"
echo "2) www.cloudflare.com"
echo "3) www.apple.com"
echo "4) www.microsoft.com"
echo "5) www.amazon.com"
echo "6) 自动测速选择最优"
read -p "输入数字 [1-6]：" sni_choice

case "$sni_choice" in
    1) SERVER_NAME="www.google.com" ;;
    2) SERVER_NAME="www.cloudflare.com" ;;
    3) SERVER_NAME="www.apple.com" ;;
    4) SERVER_NAME="www.microsoft.com" ;;
    5) SERVER_NAME="www.amazon.com" ;;
    6)
        echo "正在自动测速优选 SNI..."
        candidates=("www.google.com" "www.cloudflare.com" "www.apple.com" "www.microsoft.com" "www.amazon.com")
        best_sni=""
        best_time=99999
        for domain in "${candidates[@]}"; do
            delay=$(curl -o /dev/null -s -w "%{time_connect}\n" "https://$domain" --connect-timeout 3 || echo 99999)
            delay_int=$(echo "$delay * 1000" | bc | cut -d'.' -f1)
            echo "$domain 延迟：${delay_int}ms"
            if (( delay_int < best_time )); then
                best_time=$delay_int
                best_sni=$domain
            fi
        done
        SERVER_NAME="$best_sni"
        echo "自动选择最优 SNI：$SERVER_NAME"
        ;;
    *)
        SERVER_NAME="www.google.com"
        echo "输入错误，默认使用 www.google.com"
        ;;
esac

DEST="${SERVER_NAME}:443"

# ==========================================
# 写入 Xray 配置（协议与原版完全一致）
# ==========================================
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["8.8.8.8","1.1.1.1"]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST",
          "xver": 0,
          "serverNames": ["$SERVER_NAME"],
          "privateKey": "$PRIVATE_KEY",
          "maxTimeDiff": 0,
          "shortIds": ["$SHORT_ID"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http","tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

# 重启服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 生成分享链接
LINK="vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_NAME&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality_$IP"

# 生成 Clash 订阅
YAML_FILE="/var/www/html/reality.yaml"
mkdir -p /var/www/html
cat > $YAML_FILE <<EOF
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
dns:
  enable: true
  listen: 0.0.0.1:53
  default-nameserver: [8.8.8.8, 1.1.1.1]
  nameserver: [8.8.8.8, 1.1.1.1]
proxies:
  - name: Reality_$IP
    type: vless
    server: $IP
    port: $PORT
    uuid: $UUID
    flow: xtls-rprx-vision
    tls: false
    reality: true
    server-name: $SERVER_NAME
    public-key: $PUBLIC_KEY
    short-id: $SHORT_ID
    network: tcp
proxy-groups:
  - name: Proxy
    type: select
    proxies: [Reality_$IP]
rules:
  - MATCH,Proxy
EOF

# 启动订阅服务
if ! command -v python3 &> /dev/null; then
    apt install python3 -y
fi
cd /var/www/html && nohup python3 -m http.server $YAML_PORT > /dev/null 2>&1 &
sleep 1
SUB_URL="http://$IP:$YAML_PORT/reality.yaml"

# 展示结果
echo
echo "================= 安装完成 =================="
echo "IP：$IP"
echo "端口：$PORT"
echo "UUID：$UUID"
echo "公钥：$PUBLIC_KEY"
echo "Short ID：$SHORT_ID"
echo "SNI：$SERVER_NAME"
echo "流控：xtls-rprx-vision"
echo "============================================"
echo
echo "vless 链接："
echo "$LINK"
echo
echo "Clash 订阅地址："
echo "$SUB_URL"
echo
echo "📱 扫码添加："
qrencode -t ansiutf8 "$LINK"
echo
echo "============================================"
