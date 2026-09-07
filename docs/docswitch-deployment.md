# DocSwitch 部署说明（网页版 Word ↔ PDF）

> 前端：`site/convert/`（Cloudflare Pages + 腾讯云静态）｜ 后端：`tools/docswitch-server/`（FastAPI + LibreOffice，Docker）｜ 域名：`ai2048.net/convert/` + `ai2048.net/api/convert`

## 一、架构

```
浏览器 --/convert/-->  nginx :8081  --alias--> /var/www/ai2048/convert  (静态前端)
        --/api/convert--> nginx :8081  --proxy_pass--> 127.0.0.1:8002      (FastAPI)
```

前端在 `localhost` 时直连 `127.0.0.1:8002`，线上走同域 `/api/convert`（无需额外证书/CORS）。

## 二、本地联调

```bash
# 后端
brew install libreoffice
cd tools/docswitch-server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app:app --host 127.0.0.1 --port 8002 --reload

# 前端
cd ../../site && python3 -m http.server 5173
# 打开 http://127.0.0.1:5173/convert/
```

冒烟：

```bash
curl http://127.0.0.1:8002/api/health
curl -F file=@/path/to/a.docx -F direction=auto http://127.0.0.1:8002/api/convert -o out.pdf
curl -F file=@/path/to/a.pdf  -F direction=auto http://127.0.0.1:8002/api/convert -o out.docx
```

## 三、腾讯云部署

### 1. 起后端容器

```bash
scp -r tools/docswitch-server ubuntu@43.133.178.146:/tmp/docswitch-server
ssh ubuntu@43.133.178.146
cd /tmp/docswitch-server && docker compose up -d --build
curl -fsS http://127.0.0.1:8002/api/health
docker compose logs -f
```

持久化（可选）：将 `/tmp/docswitch-server` 移至 `~/apps/docswitch-server` 并设 `systemd` 或 `restart: unless-stopped` 已满足。

### 2. 发布前端

```bash
cd site
scp -r convert ubuntu@43.133.178.146:/tmp/ai2048_convert
ssh ubuntu@43.133.178.146 "sudo rsync -a /tmp/ai2048_convert/ /var/www/ai2048/convert/ && rm -rf /tmp/ai2048_convert && ls -R /var/www/ai2048/convert | head -n 40"
```

### 3. 改 nginx（在 8081 HTTPS server 内新增）

`/etc/nginx/sites-available/ai2048` 的 `server { listen 8081 ssl ... }` 段内加入：

```nginx
  # DocSwitch API — proxy to FastAPI
  location /api/convert {
    proxy_pass http://127.0.0.1:8002;
    proxy_request_buffering off;
    proxy_read_timeout 60s;
    proxy_send_timeout 60s;
    client_max_body_size 55m;
  }
  # DocSwitch frontend is already served as static under /var/www/ai2048,
  # so /convert/ works without extra alias if root is /var/www/ai2048.
  # If root differs, use:
  # location /convert/ { alias /var/www/ai2048/convert/; }
```

生效：

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -fsS https://ai2048.net/convert/ | head
curl -fsS https://ai2048.net/api/health  # via nginx if you also proxy /api/health, else direct 8002
curl -F file=@/tmp/test.docx https://ai2048.net/api/convert -o /tmp/out.pdf && ls -lh /tmp/out.pdf
```

> 若希望 `GET /api/health` 也经 nginx，可加 `location = /api/health { proxy_pass http://127.0.0.1:8002/api/health; }`。

## 四、Cloudflare Pages

`site/convert/` 随 `site/` 一起发布，无需额外配置：

```bash
npx wrangler pages deploy site --project-name flowbox-site
```

Cloudflare 上的前端会请求 `https://ai2048.net/api/convert`（跨域已由后端 CORS `allow_origins: *` 允许）。

## 五、运维

```bash
ssh ubuntu@43.133.178.146 "docker ps | grep docswitch; curl -fsS http://127.0.0.1:8002/api/health"
ssh ubuntu@43.133.178.146 "docker compose -f ~/apps/docswitch-server/docker-compose.yml logs -n 100"
ssh ubuntu@43.133.178.146 "sudo journalctl -u nginx -n 50; sudo nginx -t"
# 临时目录
ssh ubuntu@43.133.178.146 "ls -la /tmp/docswitch 2>&1 | head -n 20; du -sh /tmp/docswitch 2>&1"
```

- 单文件 50MB、超时 30s、并发前端限 3。
- 临时文件：`$DOCSWITCH_TMPDIR/<uuid>/`，响应后 `BackgroundTasks` 即删，`GET /api/health` 顺带清 30 分钟以上残留。
- 中文字体：容器内已装 `fonts-noto-cjk`，避免 PDF 乱码。

## 六、回滚

```bash
ssh ubuntu@43.133.178.146 "docker compose -f ~/apps/docswitch-server/docker-compose.yml down; sudo rm -rf /var/www/ai2048/convert"
# 再把 nginx 的 /api/convert location 注释掉后 reload
```

## 七、注意事项

- 不要占用 80/443，新服务一律本地端口 + nginx 反代（见 `ai2048-server-deployment.md`）。
- `soffice` 首次启动较慢，健康检查 `start_period: 15s` 已放宽。
- 扫描件 PDF（图片型）首版不支持，转出为空属预期，二期待 OCR。
