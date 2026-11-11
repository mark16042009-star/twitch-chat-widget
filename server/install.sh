#!/usr/bin/env bash
# Установка или обновление чат-сервера на Ubuntu/Debian. Запускать от root.
set -euo pipefail
REPO="https://github.com/mark16042009-star/twitch-chat-widget"
DIR="/opt/twitch-chat-widget"
PORT_FIXED="${PORT:+yes}"
PORT="${PORT:-80}"

echo "==> Устанавливаю Node.js и git"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs npm git >/dev/null

echo "==> Загружаю файлы виджета"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q --ff-only; else git clone -q --depth 1 "$REPO" "$DIR"; fi
cd "$DIR/server" && npm install --omit=dev --silent --no-audit --no-fund

# Ищем свободный порт (наш старый процесс сначала останавливаем)
systemctl stop twitch-chat 2>/dev/null || true
port_busy() {
  if command -v ss >/dev/null; then ss -ltnH "sport = :$1" | grep -q .
  else (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; fi
}
if port_busy "$PORT"; then
  echo "==> Порт $PORT уже занят:"
  command -v ss >/dev/null && ss -ltnpH "sport = :$PORT" | sed 's/^/    /'
  if [ -n "$PORT_FIXED" ]; then echo "Укажите другой порт: PORT=8081"; exit 1; fi
  for p in 8080 8081 8082 8088 8090 3000; do
    if ! port_busy "$p"; then PORT="$p"; break; fi
  done
  echo "==> Использую свободный порт $PORT"
fi

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
