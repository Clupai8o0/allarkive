FROM python:3.11-slim-bookworm

WORKDIR /app

# curl is used by HEALTHCHECK. libxml2 + libxslt are needed by lxml's manylinux
# wheel runtime on slim images (the wheel ships the .so but still links libz).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl libxml2 libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -sf http://localhost:8000/health || exit 1

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
