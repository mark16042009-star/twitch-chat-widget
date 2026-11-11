// Сервер для виджета чата:
//  - раздаёт index.html (конфигуратор) и chat.html (виджет)
//  - /irc — WebSocket-ретранслятор: браузер <-> этот сервер <-> чат Twitch
//    (помогает, если провайдер блокирует Twitch на вашем компьютере)
const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer, WebSocket } = require("ws");

const PORT = +process.env.PORT || 80;
const ROOT = path.resolve(__dirname, "..");
const TWITCH = "wss://irc-ws.chat.twitch.tv:443";
const MAX_PER_IP = 10;   // одновременных подключений с одного IP
const MAX_TOTAL = 300;   // всего подключений

const FILES = { "/": "index.html", "/index.html": "index.html", "/chat.html": "chat.html" };

// Прокси нужен только для локальных тестов; на VPS не используется
let agent;
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
if (proxy) {
  try { const { HttpsProxyAgent } = require("https-proxy-agent"); agent = new HttpsProxyAgent(proxy); }
  catch { /* модуль не установлен — подключаемся напрямую */ }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname === "/relay-status") {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    return res.end(JSON.stringify({ relay: true, clients: wss.clients.size }));
  }
  const file = FILES[url.pathname];
  if (!file) { res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" }); return res.end("Не найдено"); }
  fs.readFile(path.join(ROOT, file), (err, data) => {
    if (err) { res.writeHead(500); return res.end("Ошибка чтения файла"); }
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server, path: "/irc", maxPayload: 64 * 1024 });
const perIp = new Map();

wss.on("connection", (client, req) => {
  const ip = req.socket.remoteAddress;
  const n = (perIp.get(ip) || 0) + 1;
  if (n > MAX_PER_IP || wss.clients.size > MAX_TOTAL) { client.close(1013, "Too many connections"); return; }
  perIp.set(ip, n);

  const upstream = new WebSocket(TWITCH, { agent });
  const queue = [];

  upstream.on("open", () => { queue.splice(0).forEach(m => upstream.send(m)); });
  upstream.on("message", data => { if (client.readyState === WebSocket.OPEN) client.send(data.toString()); });
  client.on("message", data => {
    const msg = data.toString();
    if (upstream.readyState === WebSocket.OPEN) upstream.send(msg);
    else if (queue.length < 20) queue.push(msg);
  });

  const closeBoth = () => {
    if (client.readyState <= WebSocket.OPEN) client.close();
    if (upstream.readyState <= WebSocket.OPEN) upstream.terminate();
  };
  upstream.on("close", closeBoth);
  upstream.on("error", err => { console.error("[twitch]", err.message); closeBoth(); });
  client.on("error", closeBoth);
  client.on("close", () => {
    const left = (perIp.get(ip) || 1) - 1;
    left > 0 ? perIp.set(ip, left) : perIp.delete(ip);
    closeBoth();
  });
});

server.listen(PORT, () => console.log(`Чат-сервер запущен: http://0.0.0.0:${PORT}/`));
