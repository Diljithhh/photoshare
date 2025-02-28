#!/bin/bash

# Ensure we're in the backend directory
cd "$(dirname "$0")"

# Load environment variables from .env if it exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "Installing Railway CLI..."
    curl -fsSL https://railway.app/install.sh | sh
fi

# Login to Railway if not already logged in
if ! railway whoami &> /dev/null; then
    echo "Please login to Railway..."
    railway login
fi

# Remove any existing Railway link
railway unlink || true

# Link to the backend project
echo "Linking to Railway project..."
railway link

# Set environment variables
echo "Setting environment variables..."
railway variables add AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
railway variables add AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
railway variables add AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION"
railway variables add PORT="8000"

# Deploy the application
echo "Deploying backend to Railway..."
railway up --detach

# Get the deployment URL
echo "Your backend API will be available at:"
railway domain