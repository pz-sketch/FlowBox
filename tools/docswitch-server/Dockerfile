FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    libreoffice-writer \
    fonts-noto-cjk fonts-noto-color-emoji \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt ./
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

COPY app.py ./

# Non-root user
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

ENV DOCSWITCH_TMPDIR=/tmp/docswitch
EXPOSE 8002

CMD ["python3", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8002"]
