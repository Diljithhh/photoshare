#!/bin/bash

# Ensure we're in the backend directory
cd "$(dirname "$0")"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create one based on .env.example"
    exit 1
fi

# Load environment variables from .env file
set -a
source .env
set +a

# Check if required environment variables are set
required_vars=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_DEFAULT_REGION")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set in .env file"
        exit 1
    fi
done

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

# Set environment variables in Railway (one at a time)
echo "Setting environment variables..."
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ $key =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue

    # Remove any quotes from the value
    value=$(echo "$value" | tr -d '"'"'")

    # Add the variable to Railway
    echo "Adding $key to Railway..."
    railway variables add "$key=$value"
done < .env

# Deploy the application
echo "Deploying backend to Railway..."
railway up --detach

# Get the deployment URL
echo "Your backend API will be available at:"
railway domain