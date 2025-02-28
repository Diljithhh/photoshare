FROM python:3.9-slim

WORKDIR /app

# Copy only the backend requirements first
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the backend code
COPY backend/app ./app

# Expose the port
EXPOSE $PORT

# Command to run the application
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}