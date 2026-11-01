FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Create non-root system user
RUN addgroup --system app && adduser --system --ingroup app app

# Install dependencies first for optimal Docker layer caching
COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy backend application source code
COPY --chown=app:app app.py agents.py database.py rag.py tools.py ./

# Copy web frontend assets
COPY --chown=app:app web_frontend ./web_frontend

# Prepare writable runtime storage directories
RUN mkdir -p data uploads chroma_db checkpoints /app/checkpoints && \
    chown -R app:app data uploads chroma_db checkpoints /app/checkpoints

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)" || exit 1

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*", "--workers", "1"]
