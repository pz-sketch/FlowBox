"""DocSwitch — Word ↔ PDF conversion service.

Endpoints:
  GET  /api/health
  POST /api/convert  (multipart: file + direction=auto|docx2pdf|pdf2docx)

Storage: per-request UUID temp dir under DOCSWITCH_TMPDIR (default /tmp/docswitch).
Cleanup: response background task + periodic sweep of stale dirs (>30 min).
"""

from __future__ import annotations

import asyncio
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

MAX_BYTES = 50 * 1024 * 1024
ALLOWED_EXTS = {"pdf", "docx", "doc"}
TMP_ROOT = Path(__import__("os").environ.get("DOCSWITCH_TMPDIR", "/tmp/docswitch"))
CONVERT_TIMEOUT_S = 30

app = FastAPI(title="DocSwitch", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _ext(name: str) -> str:
    return Path(name).suffix.lower().lstrip(".")


def _safe_filename(name: str) -> str:
    # strip directory components, keep reasonable chars
    base = Path(name).name
    # fallback if empty
    return base if base else "file"


def _new_tmpdir() -> Path:
    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    d = TMP_ROOT / f"{uuid.uuid4().hex}"
    d.mkdir(parents=True, exist_ok=False)
    return d


def _cleanup_dir(p: Path) -> None:
    try:
        shutil.rmtree(p, ignore_errors=True)
    except Exception:
        pass


def _sweep_stale() -> int:
    """Remove tmp subdirs older than 30 min. Returns count removed."""
    if not TMP_ROOT.exists():
        return 0
    now = time.time()
    removed = 0
    for child in TMP_ROOT.iterdir():
        try:
            if not child.is_dir():
                continue
            age = now - child.stat().st_mtime
            if age > 30 * 60:
                shutil.rmtree(child, ignore_errors=True)
                removed += 1
        except Exception:
            continue
    return removed


def _run_soffice_to_pdf(src: Path, out_dir: Path) -> Path:
    """Convert doc/docx -> pdf via soffice. Returns output pdf path."""
    # soffice --headless --convert-to pdf --outdir <dir> <src>
    cmd = [
        "soffice",
        "--headless",
        "--convert-to",
        "pdf",
        "--outdir",
        str(out_dir),
        str(src),
    ]
    try:
        subprocess.run(cmd, check=True, timeout=CONVERT_TIMEOUT_S, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=f"LibreOffice not installed (soffice missing): {e}") from e
    except subprocess.TimeoutExpired as e:
        raise HTTPException(status_code=504, detail=f"Conversion timed out after {CONVERT_TIMEOUT_S}s") from e
    except subprocess.CalledProcessError as e:
        err = (e.stderr or b"").decode(errors="replace")[:800]
        raise HTTPException(status_code=500, detail=f"LibreOffice conversion failed: {err or e}") from e

    pdf_name = src.stem + ".pdf"
    out = out_dir / pdf_name
    if not out.exists():
        # soffice sometimes keeps original stem casing differently; search
        pdfs = list(out_dir.glob("*.pdf"))
        if pdfs:
            out = pdfs[0]
        else:
            raise HTTPException(status_code=500, detail="Conversion produced no PDF output")
    return out


def _run_pdf_to_docx(src: Path, dst: Path) -> None:
    """Convert pdf -> docx. Tries pdf2docx, falls back to PyMuPDF + python-docx."""
    # Try pdf2docx first (layout-aware)
    try:
        from pdf2docx import Converter  # type: ignore

        cv = Converter(str(src))
        try:
            cv.convert(str(dst))
        finally:
            cv.close()
        if dst.exists() and dst.stat().st_size > 0:
            return
    except Exception as e:
        # fall through to fallback; keep message for error reporting if that also fails
        fallback_error = e
    else:
        fallback_error = None  # type: ignore

    # Fallback: PyMuPDF extract + python-docx rebuild (plain text, one paragraph per block)
    try:
        import fitz  # PyMuPDF
        from docx import Document  # type: ignore
        from docx.shared import Pt  # noqa: F401

        doc = fitz.open(str(src))
        out = Document()
        # Use a default style; attempt to preserve page breaks
        for pi in range(len(doc)):
            page = doc[pi]
            text = page.get_text("text") or ""
            # Split into paragraphs by blank lines
            blocks = [b.strip() for b in text.split("\n") if b.strip() != ""]
            if not blocks:
                out.add_paragraph("")
            else:
                for b in blocks:
                    out.add_paragraph(b)
            if pi < len(doc) - 1:
                out.add_page_break()
        doc.close()
        out.save(str(dst))
        if dst.exists() and dst.stat().st_size > 0:
            return
    except Exception as e2:
        msg = str(fallback_error)[:400] if fallback_error else ""
        msg2 = str(e2)[:400]
        raise HTTPException(status_code=500, detail=f"PDF→DOCX failed. pdf2docx: {msg} | fallback: {msg2}") from e2

    raise HTTPException(status_code=500, detail="PDF→DOCX produced no output")


@app.get("/api/health")
async def health():
    sweep = _sweep_stale()
    return {"ok": True, "sweep_removed": sweep}


@app.post("/api/convert")
async def convert(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    direction: str = Form("auto"),
):
    raw_name = _safe_filename(file.filename or "file")
    ext = _ext(raw_name)
    if ext not in ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail=f"Unsupported file type .{ext}. Allowed: {', '.join(sorted(ALLOWED_EXTS))}")

    data = await file.read()
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"File too large ({len(data)} bytes). Limit is {MAX_BYTES} bytes (50 MB)")
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="Empty file")

    # Normalize direction
    direction = (direction or "auto").strip().lower()
    if direction not in ("auto", "docx2pdf", "pdf2docx"):
        raise HTTPException(status_code=400, detail="direction must be auto, docx2pdf, or pdf2docx")
    if direction == "auto":
        direction = "pdf2docx" if ext == "pdf" else "docx2pdf"

    # Validate direction vs extension
    if direction == "docx2pdf" and ext == "pdf":
        raise HTTPException(status_code=400, detail="direction docx2pdf requires a .docx/.doc file")
    if direction == "pdf2docx" and ext in ("docx", "doc"):
        raise HTTPException(status_code=400, detail="direction pdf2docx requires a .pdf file")

    tmpdir = _new_tmpdir()
    # Opportunistic sweep (cheap)
    _sweep_stale()

    src_path = tmpdir / raw_name
    # Avoid collisions if client name duplicates stem handling; write to src_path
    src_path.write_bytes(data)

    # For .doc -> pdf, soffice handles directly. For pdf->docx, handle directly.
    try:
        if direction == "docx2pdf":
            out_path = await asyncio.to_thread(_run_soffice_to_pdf, src_path, tmpdir)
            media_type = "application/pdf"
            download_name = Path(raw_name).stem + ".pdf"
        else:
            out_path = tmpdir / (Path(raw_name).stem + ".docx")
            await asyncio.to_thread(_run_pdf_to_docx, src_path, out_path)
            media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            download_name = Path(raw_name).stem + ".docx"

        if not out_path.exists():
            raise HTTPException(status_code=500, detail="Converter produced no output file")

        # Schedule cleanup after response is sent
        background_tasks.add_task(_cleanup_dir, tmpdir)

        # FileResponse will stream the file; background task runs after
        return FileResponse(
            path=str(out_path),
            media_type=media_type,
            filename=download_name,
            headers={"Cache-Control": "no-store"},
        )
    except HTTPException:
        _cleanup_dir(tmpdir)
        raise
    except Exception as e:
        _cleanup_dir(tmpdir)
        raise HTTPException(status_code=500, detail=str(e)[:800]) from e


@app.exception_handler(HTTPException)
async def http_exc_handler(_, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
