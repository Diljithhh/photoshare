#!/bin/bash

# Remove AWS credentials from git history
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch \
    backend/.aws/credentials \
    backend/.env \
    .env \
    **/credentials \
    **/.env" \
  --prune-empty --tag-name-filter cat -- --all

# Remove the old refs
git for-each-ref --format="delete %(refname)" refs/original/ | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Force push to remove sensitive data from GitHub
echo "Now you can force push with: git push origin main --force"