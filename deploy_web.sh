#!/bin/bash

# Exit on error
set -e

echo "Building Flutter web app..."
flutter build web --release

echo "Deploying to Firebase Hosting..."
firebase deploy --only hosting

echo "Deployment complete!"