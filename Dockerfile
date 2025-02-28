FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libffi-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy only the backend requirements first
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire backend app directory
COPY backend/app ./app

# Set default environment variables
ENV PORT=8000 \
    HOST=0.0.0.0 \
    ENVIRONMENT=production \
    ALLOWED_ORIGINS="*" \
    DATABASE_URL="sqlite:///./photoshare.db"

# Create directory for SQLite database
RUN mkdir -p /app/data

# Expose the port
EXPOSE ${PORT}

# Command to run the application
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT}