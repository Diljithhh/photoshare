from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import boto3
from botocore.exceptions import ClientError
import uuid
from typing import List
import os
from dotenv import load_dotenv
import logging

# Load environment variables
load_dotenv()

# Initialize router
router = APIRouter()

logger = logging.getLogger(__name__)

BUCKET_NAME = "screenmirror-canvas-storage"

# Initialize S3 client
logger.info("Initializing S3 client...")
try:
    s3_client = boto3.client(
        's3',
        region_name='ap-south-1',  # Mumbai region
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
    )

    # Test S3 connection
    logger.info("Testing S3 connection...")
    s3_client.list_buckets()
    logger.info("Successfully connected to S3")

    # Verify bucket exists
    logger.info(f"Verifying bucket {BUCKET_NAME} exists...")
    s3_client.head_bucket(Bucket=BUCKET_NAME)
    logger.info(f"Successfully verified bucket {BUCKET_NAME}")

except Exception as e:
    logger.error(f"Error initializing S3 client or verifying bucket: {str(e)}")
    raise

# Constants
MAX_PHOTOS = 500
EXPIRATION = 3600  # URL expiration in seconds (1 hour)

class UploadRequest(BaseModel):
    event_id: str
    num_photos: int = 1  # Default to 1 if not specified

class PresignedURLResponse(BaseModel):
    session_id: str
    presigned_urls: List[str]

@router.post("/upload", response_model=PresignedURLResponse)
async def generate_upload_urls(request: UploadRequest):
    logger = logging.getLogger(__name__)

    # Log the entire request for debugging
    logger.info(f"Received upload request: {request.dict()}")

    # Validate request parameters
    if not request.event_id:
        logger.error("Missing event_id in request")
        raise HTTPException(
            status_code=400,
            detail="event_id is required"
        )

    if request.num_photos < 1:
        logger.error(f"Invalid num_photos: {request.num_photos}")
        raise HTTPException(
            status_code=400,
            detail="num_photos must be greater than 0"
        )

    if request.num_photos > MAX_PHOTOS:
        logger.error(f"num_photos exceeds maximum limit: {request.num_photos}")
        raise HTTPException(
            status_code=400,
            detail=f"num_photos cannot exceed {MAX_PHOTOS}"
        )

    logger.info(f"Starting generate_upload_urls with event_id: {request.event_id}, num_photos: {request.num_photos}")

    # Log AWS credentials status (without exposing sensitive data)
    logger.info(f"AWS Access Key ID exists: {bool(os.getenv('AWS_ACCESS_KEY_ID'))}")
    logger.info(f"AWS Secret Access Key exists: {bool(os.getenv('AWS_SECRET_ACCESS_KEY'))}")
    logger.info(f"AWS Region: {os.getenv('AWS_DEFAULT_REGION', 'not set')}")
    logger.info(f"Using bucket: {BUCKET_NAME}")

    try:
        # Test S3 client connection
        logger.info("Testing S3 client connection...")
        buckets = s3_client.list_buckets()
        logger.info(f"Available buckets: {[b['Name'] for b in buckets['Buckets']]}")

        # Generate a unique session ID
        session_id = str(uuid.uuid4())
        logger.info(f"Generated session_id: {session_id}")

        # Generate presigned URLs for the requested number of photos
        presigned_urls = []
        logger.info(f"Generating {request.num_photos} presigned URLs")

        for i in range(request.num_photos):
            # Create a unique key for each potential photo
            file_key = f"{request.event_id}/{session_id}/{i}.jpg"
            logger.info(f"Generating presigned URL for key: {file_key}")

            try:
                # Generate presigned URL
                logger.info("Calling S3 generate_presigned_url")
                presigned_url = s3_client.generate_presigned_url(
                    'put_object',
                    Params={
                        'Bucket': BUCKET_NAME,
                        'Key': file_key,
                        'ContentType': 'image/jpeg'
                    },
                    ExpiresIn=EXPIRATION
                )
                logger.info(f"Successfully generated presigned URL for {file_key}")
                presigned_urls.append(presigned_url)

            except ClientError as e:
                error_response = e.response.get('Error', {})
                error_code = error_response.get('Code', 'Unknown')
                error_message = error_response.get('Message', str(e))
                logger.error(f"S3 ClientError while generating presigned URL: Code={error_code}, Message={error_message}")
                raise HTTPException(
                    status_code=500,
                    detail=f"Error generating presigned URL: {error_code} - {error_message}"
                )

        logger.info(f"Successfully generated {len(presigned_urls)} presigned URLs")
        return PresignedURLResponse(
            session_id=session_id,
            presigned_urls=presigned_urls
        )

    except Exception as e:
        logger.error(f"Unexpected error in generate_upload_urls: {str(e)}")
        if isinstance(e, ClientError):
            error_response = e.response.get('Error', {})
            error_code = error_response.get('Code', 'Unknown')
            error_message = error_response.get('Message', str(e))
            logger.error(f"AWS Error Details - Code: {error_code}, Message: {error_message}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate upload URLs: {str(e)}"
        )