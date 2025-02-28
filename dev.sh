#!/bin/bash

# Start FastAPI backend
cd backend
uvicorn app.main:app --reload --port 8000 &
BACKEND_PID=$!

# Start Flutter web frontend
cd ..
flutter run -d web-server --web-port 3000 &
FRONTEND_PID=$!

# Handle script termination
trap "kill $BACKEND_PID $FRONTEND_PID" EXIT

# Wait for both processes
wait