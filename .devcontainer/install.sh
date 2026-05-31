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

# ── Gaming Network Optimizations ──────────────────────────────────
echo "🎮 Applying gaming network optimizations..."

# Enable BBR congestion control (reduces packet loss significantly)
if modprobe tcp_bbr 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
  echo "net.core.default_qdisc=fq"         >> /etc/sysctl.d/99-gaming.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-gaming.conf
  echo "✅ BBR enabled"
else
  echo "⚠️  BBR not available, skipping"
fi

# TCP buffer & latency tuning
cat >> /etc/sysctl.d/99-gaming.conf << 'EOF'
# Reduce bufferbloat → lower ping spikes
net.ipv4.tcp_low_latency=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_moderate_rcvbuf=1

# TCP Fast Open (client + server)
net.ipv4.tcp_fastopen=3

# Keep-alive to recover dropped connections faster
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6

# Retransmit faster on packet loss
net.ipv4.tcp_retries2=8
net.ipv4.tcp_syn_retries=3

# Socket buffer sizes (4MB)
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.ipv4.tcp_rmem=4096 87380 4194304
net.ipv4.tcp_wmem=4096 65536 4194304

# Reduce TIME_WAIT sockets
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
EOF

sysctl -p /etc/sysctl.d/99-gaming.conf 2>/dev/null || true
echo "✅ Network tuning applied"

# ── UUID & Config ──────────────────────────────────────────────────
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "🔑 Generated UUID: $UUID"
sed -i "s/__UUID__/$UUID/" /etc/config.json

# ── Print configs script ───────────────────────────────────────────
cat > /usr/local/bin/print-configs.sh << SCRIPT
#!/bin/sh
UUID=\$(grep -o '"id": *"[^"]*"' /etc/config.json | grep -o '[0-9a-f-]\{36\}')
SNI="\${CODESPACE_NAME}-443.app.github.dev"
IRAN_TIME=\$(TZ='Asia/Tehran' date +'%b %d • %a | %H:%M')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎮 G-Tun88 CONFIGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "vless://\${UUID}@20.85.77.48:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# Moe Waffen Shangool - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@20.120.56.11:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# Liberty Cap Mangool - \${IRAN_TIME}"
echo ""
echo "vless://\${UUID}@20.207.70.99:443?encryption=none&security=tls&type=ws&sni=\${SNI}&path=%2Flive-chat# Hexe Habe Angoor - \${IRAN_TIME}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SCRIPT

chmod +x /usr/local/bin/print-configs.sh

# ── Keepalive script (written to disk for tmux to run) ─────────────
# This is baked in at image-build time so g-tun.sh can reference it
# immediately without needing to write it at runtime.
cat > /usr/local/bin/gtun-keepalive.sh << 'KAEOF'
#!/bin/bash
i=0
while true; do
    i=$(( i + 1 ))
    printf "\r[G-Tun] Keepalive tick: %d" "$i"
    # Every 60 ticks (~60 s) ping GitHub to simulate network activity
    (( i % 60 == 0 )) && curl -s -m 4 https://github.com >/dev/null 2>&1
    sleep 1
done
KAEOF
chmod +x /usr/local/bin/gtun-keepalive.sh

# ── Background-tasks script ────────────────────────────────────────
# Runs every 60 s inside a disowned bash process to:
#   1. Re-expose port 443 as public (GitHub can silently reset it)
#   2. Watchdog-restart xray if it has crashed
cat > /usr/local/bin/gtun-bg-tasks.sh << 'BGEOF'
#!/bin/bash
set +e
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/etc/config.json"
XRAY_LOG="/tmp/xray.log"
PORT=443

while true; do
    sleep 60

    # 1 – Re-expose port as public (silently; gh CLI must be authed)
    if command -v gh >/dev/null 2>&1 && [[ -n "${CODESPACE_NAME:-}" ]]; then
        GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 GH_FORCE_TTY=0 \
            gh codespace ports visibility "${PORT}:public" -c "$CODESPACE_NAME" \
            </dev/null >/dev/null 2>&1 || true
    fi

    # 2 – Watchdog: restart xray if not running
    if ! pgrep -x xray >/dev/null 2>&1; then
        sudo /usr/local/bin/xray -c "$XRAY_CONF" >>"$XRAY_LOG" 2>&1 &
        sleep 3
        # Re-expose after restart in case timing matters
        if command -v gh >/dev/null 2>&1 && [[ -n "${CODESPACE_NAME:-}" ]]; then
            GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 GH_FORCE_TTY=0 \
                gh codespace ports visibility "${PORT}:public" -c "$CODESPACE_NAME" \
                </dev/null >/dev/null 2>&1 || true
        fi
    fi
done
BGEOF
chmod +x /usr/local/bin/gtun-bg-tasks.sh

# ── Main g-tun.sh launcher ─────────────────────────────────────────
cat > /usr/local/bin/g-tun.sh << 'MAINEOF'
#!/bin/bash
# G-Tun88 auto keep-alive launcher
# Called by postStartCommand (--silent-start) and postAttachCommand (normal)

set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/etc/config.json"
XRAY_LOG="/tmp/xray.log"
PORT=443
BG_PID_FILE="/tmp/gtun_bg.pid"
TMUX_SESSION="gtun_keepalive"

# ── Helpers ────────────────────────────────────────────────────────

xray_running() {
    pgrep -x xray >/dev/null 2>&1
}

expose_port() {
    command -v gh >/dev/null 2>&1 || return 0
    [[ -z "${CODESPACE_NAME:-}" ]] && return 0
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1 GH_FORCE_TTY=0 \
        gh codespace ports visibility "${PORT}:public" -c "$CODESPACE_NAME" \
        </dev/null >/dev/null 2>&1 || true
}

start_xray() {
    xray_running && return 0
    sudo "$XRAY_BIN" -c "$XRAY_CONF" >>"$XRAY_LOG" 2>&1 &
    sleep 2
}

# ── Anti-sleep tmux engine ─────────────────────────────────────────
enable_anti_sleep() {
    tmux has-session -t "$TMUX_SESSION" 2>/dev/null && return 0
    tmux new-session -d -s "$TMUX_SESSION" \
        "bash /usr/local/bin/gtun-keepalive.sh" 2>/dev/null || true
}

# ── Background watchdog/port-refresh loop ─────────────────────────
start_background_tasks() {
    # Guard: don't spawn a second copy if one is already alive
    if [[ -f "$BG_PID_FILE" ]]; then
        local pid
        pid=$(cat "$BG_PID_FILE" 2>/dev/null || true)
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    bash /usr/local/bin/gtun-bg-tasks.sh </dev/null >/dev/null 2>&1 &
    printf '%s\n' $! > "$BG_PID_FILE"
    disown 2>/dev/null || true
}

# ── Silent-start mode (postStartCommand) ──────────────────────────
# Runs before the user attaches. Starts xray + background systems
# quietly so everything is live by the time the terminal opens.
if [[ "${1:-}" == "--silent-start" ]]; then
    start_xray
    expose_port
    start_background_tasks
    enable_anti_sleep
    exit 0
fi

# ── Normal attach mode (postAttachCommand) ─────────────────────────
# Ensure xray is up (it should be from silent-start, but be safe),
# expose port, start background tasks if not already running,
# then print configs for the user.

# Wait briefly for the environment to stabilise
echo "[G-Tunnel] Environment ready. Starting keep-alive systems..."

start_xray
expose_port
start_background_tasks
enable_anti_sleep

echo "[G-Tunnel] ✔ Xray running | Port public | Watchdog active | Anti-sleep active"
echo ""

/usr/local/bin/print-configs.sh
MAINEOF
chmod +x /usr/local/bin/g-tun.sh

# Print configs at end of install (UUID was just written above)
/usr/local/bin/print-configs.sh
