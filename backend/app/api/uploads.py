from fastapi import APIRouter, File, UploadFile, Form, HTTPException, Depends
import boto3
from botocore.exceptions import ClientError
import uuid
from typing import List
import os
from dotenv import load_dotenv
import logging
import io
from pydantic import BaseModel

# Load environment variables
load_dotenv()

# Initialize router with prefix to prevent duplication
router = APIRouter(prefix="/api/v1")

logger = logging.getLogger(__name__)

# Use your bucket name
BUCKET_NAME = "screenmirror-canvas-storage"

# Initialize S3 client as a dependency
def get_s3_client():
    # Check if we're in local development mode
    is_development = os.getenv("ENVIRONMENT") == "development"

    # For local development, you can use a mock client or the real one with clear error messages
    if is_development:
        logger.info("Using S3 client in development mode")

        # Option 1: Use real client with better error handling
        try:
            return boto3.client(
                's3',
                region_name='ap-south-1',
                aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
                aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
            )
        except Exception as e:
            logger.error(f"Failed to initialize S3 client: {str(e)}")
            # In local development, we can continue with a mock client
            logger.info("Falling back to mock S3 client for local development")

            # Create a mock client for local development
            class MockS3Client:
                def upload_fileobj(self, file_object, bucket, key, **kwargs):
                    logger.info(f"MOCK S3: Would upload to {bucket}/{key}")
                    # In a real implementation, you might save this to a local folder
                    return True

                def generate_presigned_url(self, client_method, params, **kwargs):
                    logger.info(f"MOCK S3: Would generate presigned URL for {params}")
                    # Return a dummy local URL for testing
                    return f"http://localhost:8000/mock-s3/{params.get('Bucket', 'bucket')}/{params.get('Key', 'key')}"

            return MockS3Client()

    # For production, use the real client
    return boto3.client(
        's3',
        region_name='ap-south-1',
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
    )

@router.post("/upload-photo")
async def upload_photo(
    event_id: str = Form(...),
    file: UploadFile = File(...),
    s3_client = Depends(get_s3_client)
):
    """
    Upload a single photo directly to S3 bucket
    """
    logger.info(f"Processing upload for event_id: {event_id}, filename: {file.filename}")

    if not file.filename:
        raise HTTPException(status_code=400, detail="Empty filename")

    try:
        # Generate a unique ID for the file
        file_id = str(uuid.uuid4())

        # Create a unique key for the file
        file_key = f"{event_id}/{file_id}/{file.filename}"
        logger.info(f"Generated S3 key: {file_key}")

        # Create a BytesIO object from the file content
        file_object = io.BytesIO(await file.read())

        # Upload to S3 using the file object
        logger.info(f"Uploading file to S3: {file_key}")
        s3_client.upload_fileobj(
            file_object,
            BUCKET_NAME,
            file_key,
            ExtraArgs={
                "ContentType": file.content_type
            }
        )
        logger.info(f"Successfully uploaded file to S3: {file_key}")

        # Generate a URL to access the file (if public)
        file_url = f"https://{BUCKET_NAME}.s3.ap-south-1.amazonaws.com/{file_key}"

        return {
            "success": True,
            "file_id": file_id,
            "file_key": file_key,
            "file_url": file_url
        }

    except ClientError as e:
        error_message = str(e)
        logger.error(f"S3 ClientError while uploading file: {error_message}")
        raise HTTPException(status_code=500, detail=f"Error uploading file: {error_message}")
    except Exception as e:
        logger.error(f"Unexpected error in upload_photo: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to upload photo: {str(e)}")
    finally:
        await file.close()

@router.post("/upload-multiple-photos")
async def upload_multiple_photos(
    event_id: str = Form(...),
    files: List[UploadFile] = File(...),
    s3_client = Depends(get_s3_client)
):
    """
    Upload multiple photos directly to S3 bucket
    """
    logger.info(f"Processing multiple uploads for event_id: {event_id}, file count: {len(files)}")

    if not files:
        raise HTTPException(status_code=400, detail="No files uploaded")

    results = []
    errors = []

    # Generate a unique session ID for this batch
    session_id = str(uuid.uuid4())
    logger.info(f"Generated session_id for batch upload: {session_id}")

    # Check if we're in local development mode
    is_development = os.getenv("ENVIRONMENT") == "development"

    # Log AWS credentials for debugging (ONLY in development mode)
    if is_development:
        logger.info(f"AWS Access Key ID: {os.getenv('AWS_ACCESS_KEY_ID')}")
        logger.info(f"AWS Region: ap-south-1")
        logger.info(f"S3 Bucket: {BUCKET_NAME}")

    for file in files:
        try:
            if not file.filename:
                errors.append({"error": "Empty filename"})
                continue

            # Create a unique key for the file
            file_key = f"{event_id}/{session_id}/{file.filename}"

            # Log detailed information in development mode
            if is_development:
                logger.info(f"Processing file: {file.filename}")
                logger.info(f"File size: approximately {len(await file.read())} bytes")
                await file.seek(0)  # Reset file position after reading

            # Create a BytesIO object from the file content
            file_object = io.BytesIO(await file.read())

            # Upload to S3 using the file object
            logger.info(f"Uploading file to S3: {file_key}")
            try:
                s3_client.upload_fileobj(
                    file_object,
                    BUCKET_NAME,
                    file_key,
                    ExtraArgs={
                        "ContentType": file.content_type
                    }
                )
                logger.info(f"Successfully uploaded file to S3: {file_key}")
            except ClientError as s3_error:
                logger.error(f"S3 Client Error: {str(s3_error)}")
                if is_development:
                    logger.error(f"S3 Error Response: {s3_error.response if hasattr(s3_error, 'response') else 'No response details'}")
                raise HTTPException(status_code=500, detail=f"S3 upload failed: {str(s3_error)}")
            except Exception as upload_error:
                logger.error(f"Unexpected upload error: {str(upload_error)}")
                raise HTTPException(status_code=500, detail=f"Unexpected upload error: {str(upload_error)}")

            # Generate a URL to access the file (if public)
            file_url = f"https://{BUCKET_NAME}.s3.ap-south-1.amazonaws.com/{file_key}"

            results.append({
                "filename": file.filename,
                "file_key": file_key,
                "file_url": file_url
            })
        except HTTPException as he:
            # Re-raise HTTP exceptions
            raise he
        except Exception as e:
            logger.error(f"Error uploading file {file.filename}: {str(e)}")
            # In development mode, include more detailed error information
            if is_development:
                import traceback
                logger.error(f"Detailed error: {traceback.format_exc()}")

            errors.append({
                "filename": file.filename,
                "error": str(e)
            })
        finally:
            await file.close()

    return {
        "success": len(results) > 0,
        "session_id": session_id,
        "uploaded_files": results,
        "errors": errors if errors else None
    }

# Keep the original presigned URL functionality with a different endpoint name
class UploadRequest(BaseModel):
    event_id: str
    num_photos: int = 1  # Default to 1 if not specified

class PresignedURLResponse(BaseModel):
    session_id: str
    presigned_urls: List[str]

@router.post("/generate-upload-urls", response_model=PresignedURLResponse)
async def generate_upload_urls(
    request: UploadRequest,
    s3_client = Depends(get_s3_client)
):
    """Generate presigned URLs for client-side uploads"""
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

    MAX_PHOTOS = 500
    if request.num_photos > MAX_PHOTOS:
        logger.error(f"num_photos exceeds maximum limit: {request.num_photos}")
        raise HTTPException(
            status_code=400,
            detail=f"num_photos cannot exceed {MAX_PHOTOS}"
        )

    try:
        # Generate a unique session ID
        session_id = str(uuid.uuid4())
        logger.info(f"Generated session_id: {session_id}")

        # Generate presigned URLs for the requested number of photos
        presigned_urls = []
        logger.info(f"Generating {request.num_photos} presigned URLs")

        EXPIRATION = 3600  # URL expiration in seconds (1 hour)
        for i in range(request.num_photos):
            # Create a unique key for each potential photo
            file_key = f"{request.event_id}/{session_id}/{i}.jpg"
            logger.info(f"Generating presigned URL for key: {file_key}")

            # Generate presigned URL
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

        logger.info(f"Successfully generated {len(presigned_urls)} presigned URLs")
        return PresignedURLResponse(
            session_id=session_id,
            presigned_urls=presigned_urls
        )

    except ClientError as e:
        error_response = e.response.get('Error', {})
        error_code = error_response.get('Code', 'Unknown')
        error_message = error_response.get('Message', str(e))
        logger.error(f"S3 ClientError: Code={error_code}, Message={error_message}")
        raise HTTPException(
            status_code=500,
            detail=f"Error generating presigned URL: {error_code} - {error_message}"
        )
    except Exception as e:
        logger.error(f"Unexpected error in generate_upload_urls: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate upload URLs: {str(e)}"
        )

@router.get("/test-s3", response_model=dict)
async def test_s3_connection(s3_client = Depends(get_s3_client)):
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

@router.get("/proxy-image")
async def proxy_image(
    url: str,
    s3_client = Depends(get_s3_client)
):
    """
    Proxy for S3 images in local development to handle CORS and authentication

    This endpoint takes a URL parameter which is the path to the S3 object
    and returns the image data directly, handling the S3 authentication
    """
    # Only allow this in development mode for security
    is_development = os.getenv("ENVIRONMENT") == "development"
    if not is_development:
        raise HTTPException(status_code=403, detail="This endpoint is only available in development mode")

    # Log the request for debugging
    logger.info(f"Proxying S3 image: {url}")

    try:
        # Parse the URL to extract the key
        # The URL should be in the format:
        # /bucket-name/key or just the key if we know the bucket
        if url.startswith('/'):
            # If it starts with '/', it might include the bucket name
            parts = url.strip('/').split('/', 1)
            if len(parts) == 2 and parts[0] == BUCKET_NAME:
                # Format: /bucket-name/key
                object_key = parts[1]
            else:
                # Format: /key (bucket is not specified, use default)
                object_key = url.lstrip('/')
        else:
            # Directly use as key
            object_key = url

        logger.info(f"Retrieving S3 object: {BUCKET_NAME}/{object_key}")

        # Get the object from S3
        try:
            # Try to get the object from S3
            response = s3_client.get_object(Bucket=BUCKET_NAME, Key=object_key)

            # Get the file content
            file_content = response['Body'].read()

            # Determine the content type or default to image/jpeg
            content_type = response.get('ContentType', 'image/jpeg')

            # Return the file content with appropriate headers
            # This bypasses CORS and authentication issues
            from fastapi.responses import Response
            return Response(
                content=file_content,
                media_type=content_type
            )
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code')
            logger.error(f"S3 ClientError: {error_code} - {str(e)}")

            if error_code == 'NoSuchKey':
                raise HTTPException(status_code=404, detail="Image not found")
            else:
                raise HTTPException(status_code=500, detail=f"S3 error: {error_code}")

    except Exception as e:
        logger.error(f"Error proxying image: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to proxy image: {str(e)}")