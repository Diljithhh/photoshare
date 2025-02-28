#!/bin/bash

# Ensure we're in the backend directory
cd "$(dirname "$0")"

# Create .elasticbeanstalk directory if it doesn't exist
mkdir -p .elasticbeanstalk

# Load environment variables from .env file
set -a
source .env
set +a

# Create AWS credentials directory if it doesn't exist
mkdir -p ~/.aws

# Create or update AWS credentials file
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
region=$AWS_DEFAULT_REGION
EOF

# Create or update AWS config file
cat > ~/.aws/config << EOF
[default]
region=$AWS_DEFAULT_REGION
output=json
EOF

# Initialize Elastic Beanstalk if not already done
if [ ! -f .elasticbeanstalk/config.yml ]; then
    eb init -p docker -r ap-south-1 photoshare
fi

# Create the environment if it doesn't exist
if ! eb status photoshare-api 2>/dev/null; then
    eb create photoshare-api \
        --instance_type t2.micro \
        --single \
        --envvars "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY,AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"
else
    # Deploy to existing environment
    eb deploy photoshare-api
fi