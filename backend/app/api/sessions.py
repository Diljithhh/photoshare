from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
import boto3
from botocore.exceptions import ClientError
import uuid
from typing import List
import os
from dotenv import load_dotenv
import logging
from ..models.session import CreateSessionRequest, SessionResponse
from ..utils.password import generate_random_password, hash_password
from datetime import datetime


# Load environment variables
load_dotenv()

# Initialize router with prefix
router = APIRouter(prefix="/api/v1")

logger = logging.getLogger(__name__)

# Initialize DynamoDB client as a dependency
def get_dynamodb_client():
    return boto3.resource(
        'dynamodb',
        region_name='ap-south-1',
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
    )

# Table name for sessions
TABLE_NAME = "photo_sessions_share"

# Base URL for session links
# For local testing, default to localhost
BASE_URL = os.getenv('FRONTEND_URL', os.getenv('BASE_URL', 'http://localhost:3000'))

@router.post("/session/create", response_model=SessionResponse)
async def create_session(
    request: CreateSessionRequest,
    dynamodb = Depends(get_dynamodb_client)
):
    """
    Create a new photo viewing session with password protection
    """
    logger.info(f"Creating session for event_id: {request.event_id} with {len(request.photo_urls)} photos")

    try:
        # Get the table
        table = dynamodb.Table(TABLE_NAME)

        # Generate a unique session ID
        session_id = str(uuid.uuid4())

        # Generate a random password
        password = generate_random_password(6)

        # Hash the password for storage
        hashed_password = hash_password(password)

        # Create the session link
        session_link = f"{BASE_URL}/session/{session_id}"

        # Store session data in DynamoDB
        table.put_item(
            Item={
                'session_id': session_id,
                'event_id': request.event_id,
                'hashed_password': hashed_password,
                'photo_urls': request.photo_urls,
                'created_at': int(datetime.now().timestamp())
            }
        )

        logger.info(f"Successfully created session with ID: {session_id}")

        # Return the session details
        return SessionResponse(
            session_id=session_id,
            session_link=session_link,
            password=password
        )

    except ClientError as e:
        error_message = str(e)
        logger.error(f"DynamoDB ClientError: {error_message}")
        raise HTTPException(status_code=500, detail=f"Error creating session: {error_message}")
    except Exception as e:
        logger.error(f"Unexpected error in create_session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to create session: {str(e)}")
