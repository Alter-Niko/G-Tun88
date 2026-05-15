#!/bin/sh

set -e

echo "📥 Downloading Xray Core v26.3.27..."
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip

echo "📂 Installing Xray..."
unzip -o /tmp/xray.zip -d /tmp/xray_dist
chmod +x /tmp/xray_dist/xray
mv /tmp/xray_dist/xray /usr/local/bin/xray

echo "🧹 Cleaning up..."
rm -rf /tmp/xray.zip /tmp/xray_dist

echo "✅ Xray installed successfully!"

# Generate a random UUID (RFC 4122 v4)
UUID=$(cat /proc/sys/kernel/random/uuid)

echo "🔑 Generated UUID: $UUID"

# Patch config.json with the new UUID
sed -i "s/__UUID__/$UUID/" /etc/config.json

# Write startup script that prints all VLESS configs on attach
cat > /usr/local/bin/print-configs.sh << SCRIPT
#!/bin/sh
UUID=\$(grep -o '"id": *"[^"]*"' /etc/config.json | grep -o '[0-9a-f-]\{36\}')
SNI="\${CODESPACE_NAME}-443.app.github.dev"
IRAN_TIME=\$(TZ='Asia/Tehran' date +'%H:%M')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 GHTUN VLESS CONFIGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "vless://\${UUID}@63.141.252.203:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# US1 - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@142.54.178.211:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# US2 - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@50.7.87.2:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# DE1 - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@204.12.196.34:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# US3 - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@50.7.87.5:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# DE2 - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@50.7.87.4:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# DE3 - \${IRAN_TIME}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SCRIPT

chmod +x /usr/local/bin/print-configs.sh

# Add to bash startup so it prints on every attach
echo '/usr/local/bin/print-configs.sh' >> /etc/bash.bashrc
