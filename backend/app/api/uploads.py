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

# Use a bucket name pattern that matches a common AWS naming convention
# The bucket name should be lowercase with hyphens, not spaces
BUCKET_NAME = "photoshare-uploads"

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
    bucket_list = s3_client.list_buckets()
    logger.info(f"Available buckets: {[b['Name'] for b in bucket_list['Buckets']]}")

    # Find a suitable bucket from the available ones
    available_buckets = [b['Name'] for b in bucket_list['Buckets']]
    logger.info(f"Looking for suitable bucket from available buckets: {available_buckets}")

    if BUCKET_NAME in available_buckets:
        logger.info(f"Found configured bucket: {BUCKET_NAME}")
    else:
        # Try to find a suitable bucket or use the first available one
        if available_buckets:
            BUCKET_NAME = available_buckets[0]
            logger.info(f"Using first available bucket: {BUCKET_NAME}")
        else:
            logger.error("No buckets found in AWS account")
            raise Exception("No buckets found in AWS account")

    # Verify bucket exists
    logger.info(f"Verifying bucket {BUCKET_NAME} exists...")
    s3_client.head_bucket(Bucket=BUCKET_NAME)
    logger.info(f"Successfully verified bucket {BUCKET_NAME}")

except ClientError as e:
    error_response = e.response.get('Error', {})
    error_code = error_response.get('Code', 'Unknown')
    error_message = error_response.get('Message', str(e))
    logger.error(f"AWS Error: Code={error_code}, Message={error_message}")
    logger.error(f"Error initializing S3 client or verifying bucket: {str(e)}")
    raise
except Exception as e:
    logger.error(f"Unexpected error initializing S3: {str(e)}")
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
        try:
            buckets = s3_client.list_buckets()
            logger.info(f"Available buckets: {[b['Name'] for b in buckets['Buckets']]}")

            # Check if our target bucket exists in the list
            bucket_exists = False
            for bucket in buckets['Buckets']:
                if bucket['Name'] == BUCKET_NAME:
                    bucket_exists = True
                    break

            if not bucket_exists:
                logger.error(f"Target bucket '{BUCKET_NAME}' not found in available buckets")
                raise HTTPException(
                    status_code=500,
                    detail=f"Target bucket '{BUCKET_NAME}' not found in AWS account"
                )
        except ClientError as e:
            error_response = e.response.get('Error', {})
            error_code = error_response.get('Code', 'Unknown')
            error_message = error_response.get('Message', str(e))
            logger.error(f"Failed to list buckets: Code={error_code}, Message={error_message}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to connect to AWS S3: {error_code} - {error_message}"
            )

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
                logger.info(f"URL length: {len(presigned_url)} characters")
                # Log a truncated version of the URL for debugging (first 50 chars)
                logger.info(f"URL preview: {presigned_url[:50]}...")
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
        response = PresignedURLResponse(
            session_id=session_id,
            presigned_urls=presigned_urls
        )
        # Log the first URL (truncated) to verify it's being returned correctly
        if presigned_urls:
            logger.info(f"First URL in response (truncated): {presigned_urls[0][:50]}...")
        return response

    except HTTPException:
        # Re-raise HTTP exceptions without wrapping them
        raise
    except Exception as e:
        logger.error(f"Unexpected error in generate_upload_urls: {str(e)}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        if isinstance(e, ClientError):
            error_response = e.response.get('Error', {})
            error_code = error_response.get('Code', 'Unknown')
            error_message = error_response.get('Message', str(e))
            logger.error(f"AWS Error Details - Code: {error_code}, Message: {error_message}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate upload URLs: {str(e)}"
        )

@router.get("/test-s3", response_model=dict)
async def test_s3_connection():
    """Test endpoint to verify S3 connectivity and bucket configuration"""
    try:
        # Check S3 connection
        buckets = s3_client.list_buckets()
        bucket_names = [b['Name'] for b in buckets['Buckets']]

        # Verify our bucket exists
        bucket_exists = BUCKET_NAME in bucket_names

        # Try to create a test object with a presigned URL
        test_key = f"test-{uuid.uuid4()}.txt"
        test_presigned_url = None

        try:
            test_presigned_url = s3_client.generate_presigned_url(
                'put_object',
                Params={
                    'Bucket': BUCKET_NAME,
                    'Key': test_key,
                    'ContentType': 'text/plain'
                },
                ExpiresIn=60
            )
        except Exception as e:
            logger.error(f"Error generating test presigned URL: {str(e)}")
            return {
                "status": "error",
                "message": f"Error generating test presigned URL: {str(e)}",
                "buckets": bucket_names,
                "current_bucket": BUCKET_NAME,
                "bucket_exists": bucket_exists
            }

        return {
            "status": "success",
            "message": "S3 connection successful",
            "buckets": bucket_names,
            "current_bucket": BUCKET_NAME,
            "bucket_exists": bucket_exists,
            "test_presigned_url": test_presigned_url[:50] + "..." if test_presigned_url else None
        }
    except Exception as e:
        logger.error(f"Error testing S3 connection: {str(e)}")
        return {
            "status": "error",
            "message": f"Error testing S3 connection: {str(e)}"
        }