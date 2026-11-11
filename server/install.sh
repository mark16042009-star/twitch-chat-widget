#!/usr/bin/env bash
# Установка или обновление чат-сервера на Ubuntu/Debian. Запускать от root.
set -euo pipefail
REPO="https://github.com/mark16042009-star/twitch-chat-widget"
DIR="/opt/twitch-chat-widget"
PORT="${PORT:-80}"

echo "==> Устанавливаю Node.js и git"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs npm git >/dev/null

echo "==> Загружаю файлы виджета"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q --ff-only; else git clone -q --depth 1 "$REPO" "$DIR"; fi
cd "$DIR/server" && npm install --omit=dev --silent --no-audit --no-fund

echo "==> Настраиваю автозапуск"
cat > /etc/systemd/system/twitch-chat.service <<UNIT
[Unit]
Description=Twitch chat widget server
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$DIR/server
ExecStart=/usr/bin/node $DIR/server/server.js
Environment=PORT=$PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable -q twitch-chat
systemctl restart twitch-chat

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow "$PORT"/tcp >/dev/null
fi

sleep 2
IP=$(hostname -I | awk "{print \$1}")
if systemctl is-active -q twitch-chat; then
  [ "$PORT" = "80" ] && URL="http://$IP/" || URL="http://$IP:$PORT/"
  echo
  echo "Готово! Откройте в браузере: $URL"
else
  echo "Не запустилось. Последние строки журнала:"
  journalctl -u twitch-chat -n 20 --no-pager
  exit 1
fi
