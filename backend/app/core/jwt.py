from fastapi import APIRouter, HTTPException, Depends, status, Path
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
import boto3
from botocore.exceptions import ClientError
import os
from dotenv import load_dotenv
import logging
import jwt
from datetime import datetime, timedelta, timezone
from typing import List, Optional
import bcrypt

# Load environment variables
load_dotenv()

# Initialize router with prefix
router = APIRouter(prefix="/api/v1")

logger = logging.getLogger(__name__)

# JWT Settings
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

# DynamoDB settings
TABLE_NAME = "photo_sessions_share"

# OAuth2 scheme for JWT
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token", auto_error=False)

# Initialize DynamoDB client as a dependency
def get_dynamodb_client():
    return boto3.resource(
        'dynamodb',
        region_name='ap-south-1',
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
    )
