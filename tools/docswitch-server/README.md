# DocSwitch Server

FastAPI 后端：Word ↔ PDF 互转。`docx/doc → pdf` 走 LibreOffice `soffice`，`pdf → docx` 优先 `pdf2docx`、兜底 `PyMuPDF + python-docx`。

## 本地运行（macOS）

```bash
brew install libreoffice
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app:app --host 127.0.0.1 --port 8002 --reload
curl http://127.0.0.1:8002/api/health
curl -F file=@sample.docx -F direction=auto http://127.0.0.1:8002/api/convert -o out.pdf
```

## Docker

```bash
docker compose up -d --build
curl http://127.0.0.1:8002/api/health
docker compose logs -f
```

## 前端联调

前端在 `site/convert/`，本地静态预览：

```bash
cd ../../site && python3 -m http.server 5173
# 打开 http://127.0.0.1:5173/convert/
# 前端默认：localhost 时请求 http://127.0.0.1:8002，其余走 /api/convert
```

线上 nginx 见 `docs/docswitch-deployment.md`。

## 接口

- `GET /api/health` → `{ ok: true }`
- `POST /api/convert` multipart `file` + `direction=auto|docx2pdf|pdf2docx` → 文件流（`Content-Disposition: attachment`）
  - 限制：单文件 50MB，超时 30s
  - 临时目录：`$DOCSWITCH_TMPDIR`（默认 `/tmp/docswitch`），响应后即删 + 30 分钟兜底清理
