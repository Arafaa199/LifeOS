# Receipt Ingestion Service
# Runs on nexus server for automated receipt processing

FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY carrefour_parser.py .
COPY receipt_ingestion.py .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Create directories for secrets and data (will be mounted)
RUN mkdir -p /secrets /data/receipts

# Environment defaults
ENV NEXUS_HOST=localhost \
    NEXUS_PORT=5432 \
    NEXUS_DB=nexus \
    NEXUS_USER=nexus \
    GMAIL_LABEL="LifeOS/Receipts/Carrefour" \
    SECRETS_DIR=/secrets \
    DATA_DIR=/data

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--all"]
