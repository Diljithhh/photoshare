from fastapi import APIRouter, File, UploadFile, Form, HTTPException, Depends, Header, Request
import boto3
from botocore.exceptions import ClientError
import botocore
import uuid
from typing import List
import os
from dotenv import load_dotenv
import logging
import io
from pydantic import BaseModel
from fastapi.responses import Response, JSONResponse
from urllib.parse import urlparse, parse_qs
import base64
import httpx





from fastapi.middleware.cors import CORSMiddleware


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

@router.post("/refresh-image-url")
async def refresh_image_url(
    request: dict,
    s3_client = Depends(get_s3_client),
    authorization: str = Header(None)
):
    """
    Refresh an expired presigned URL for an S3 image

    This endpoint is intended to be used when a presigned URL has expired in production
    and needs to be refreshed. It takes a path and generates a new presigned URL.
    """
    logger.info(f"Request to refresh image URL: {request}")

    # Verify authorization token (basic check)
    if not authorization or not authorization.startswith("Bearer "):
        logger.error("Missing or invalid authorization header")
        raise HTTPException(status_code=401, detail="Unauthorized")

    # Check if the request contains a path
    if "path" not in request:
        logger.error("Missing path parameter")
        raise HTTPException(status_code=400, detail="Missing path parameter")

    path = request["path"]
    logger.info(f"Refreshing URL for path: {path}")

    try:
        # Extract the key from the path
        # The path is typically in the format /bucket-name/key or just /key
        if path.startswith('/'):
            parts = path.strip('/').split('/', 1)
            if len(parts) == 2 and parts[0] == BUCKET_NAME:
                # Format: /bucket-name/key
                object_key = parts[1]
            else:
                # Format: /key (bucket is not specified, use default)
                object_key = path.lstrip('/')
        else:
            # Directly use as key
            object_key = path

        logger.info(f"Extracted S3 object key: {object_key}")

        # Verify that the object exists
        try:
            s3_client.head_object(Bucket=BUCKET_NAME, Key=object_key)
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                logger.error(f"Object does not exist: {BUCKET_NAME}/{object_key}")
                raise HTTPException(status_code=404, detail="Image not found")
            else:
                logger.error(f"Error checking object existence: {str(e)}")
                raise HTTPException(status_code=500, detail=f"S3 error: {str(e)}")

        # Generate a new presigned URL with longer expiration
        EXPIRATION = 7200  # 2 hours (adjust as needed)

        # Determine content type based on file extension
        content_type = "image/jpeg"  # Default
        if object_key.lower().endswith('.png'):
            content_type = "image/png"
        elif object_key.lower().endswith('.gif'):
            content_type = "image/gif"
        elif object_key.lower().endswith('.webp'):
            content_type = "image/webp"

        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': object_key,
                'ResponseContentType': content_type
            },
            ExpiresIn=EXPIRATION
        )

        logger.info(f"Generated new presigned URL for {object_key} with {EXPIRATION}s expiration")

        return {
            "success": True,
            "presigned_url": presigned_url,
            "expires_in": EXPIRATION
        }
    except ClientError as e:
        error_response = e.response.get('Error', {})
        error_code = error_response.get('Code', 'Unknown')
        error_message = error_response.get('Message', str(e))
        logger.error(f"S3 ClientError while refreshing URL: Code={error_code}, Message={error_message}")
        raise HTTPException(
            status_code=500,
            detail=f"Error refreshing URL: {error_code} - {error_message}"
        )
    except Exception as e:
        logger.error(f"Unexpected error in refresh_image_url: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to refresh image URL: {str(e)}"
        )

@router.get("/direct-access")
async def direct_access(url: str, request: Request):
    """
    Endpoint to proxy image requests directly, bypassing CORS restrictions.
    Works in both development and production environments.

    Takes a URL parameter pointing to the image to proxy.
    Returns the image data with appropriate content type.
    """
    logger.info(f"Direct access request for URL: {url}")

    # Get config or use defaults
    if hasattr(request.app.state, 'config'):
        config = request.app.state.config
        logger.info(f"Using app state config")
    else:
        # Fallback configuration
        logger.warning("No app state config found, using fallback config")
        from pydantic import BaseModel
        class FallbackConfig(BaseModel):
            AWS_BUCKET_NAME: str = "screenmirror-canvas-storage"
        config = FallbackConfig()

    # Get S3 client - either from app state or create a new one
    if hasattr(request.app.state, 's3_client'):
        client = request.app.state.s3_client
        logger.info("Using app state S3 client")
    else:
        logger.warning("Creating new S3 client as none found in app state")
        client = boto3.client(
            's3',
            region_name='ap-south-1',
            aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
            aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
        )

    try:
        # Log request headers for debugging
        logger.info(f"Request headers: {request.headers}")
        origin = request.headers.get('origin', 'unknown')
        logger.info(f"Request origin: {origin}")

        # Check if the origin is allowed
        allowed_origins = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app").split(",")
        allowed_origins = [o.strip() for o in allowed_origins if o.strip()]

        # In development, allow localhost
        if os.getenv("ENVIRONMENT") == "development":
            allowed_origins.append("http://localhost:3000")

        # For testing, you can uncomment this line to allow all origins
        # allowed_origins.append("*")

        # If the origin is not in our allowed list, set default
        if origin != "unknown" and origin not in allowed_origins and "*" not in allowed_origins:
            logger.warning(f"Origin {origin} not in allowed origins: {allowed_origins}")
            # We will continue processing but will set the correct CORS headers later

        # Security check - only allow S3 URLs
        parsed_url = urlparse(url)
        is_s3_url = ".s3." in parsed_url.netloc or "s3.amazonaws.com" in parsed_url.netloc

        if not is_s3_url:
            logger.warning(f"Attempted to proxy non-S3 URL: {url}")
            return JSONResponse(
                status_code=403,
                content={"detail": "Only S3 URLs can be proxied for security reasons"},
                headers={
                    "Access-Control-Allow-Origin": origin,
                    "Access-Control-Allow-Credentials": "true",
                    "Access-Control-Allow-Methods": "GET, OPTIONS",
                    "Access-Control-Allow-Headers": "*"
                }
            )

        # Fetch the actual image data
        # client = request.app.state.s3_client
        # (Don't use the above line as we now have client defined earlier)

        # Extract bucket and key from URL
        if parsed_url.netloc.startswith('s3.amazonaws.com'):
            # Format: s3.amazonaws.com/bucket-name/key-path
            path_parts = parsed_url.path.strip('/').split('/', 1)
            if len(path_parts) < 2:
                return JSONResponse(
                    status_code=400,
                    content={"detail": "Invalid S3 URL format"}
                )
            bucket_name = path_parts[0]
            object_key = path_parts[1]
        elif '.s3.' in parsed_url.netloc:
            # Format: bucket-name.s3.region.amazonaws.com/key-path
            bucket_name = parsed_url.netloc.split('.s3.')[0]
            object_key = parsed_url.path.strip('/')
        else:
            # For presigned URLs, parse the query parameters to find the bucket and key
            query_params = parse_qs(parsed_url.query)
            if 'X-Amz-Credential' in query_params:
                # Extract from X-Amz-Credential parameter
                credential = query_params['X-Amz-Credential'][0]
                # Example format: AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request
                bucket_name = config.AWS_BUCKET_NAME  # Default to configured bucket
                object_key = parsed_url.path.strip('/')
            else:
                return JSONResponse(
                    status_code=400,
                    content={"detail": "Could not determine S3 bucket and key"}
                )

        logger.info(f"Accessing S3 object: bucket={bucket_name}, key={object_key}")

        try:
            # Get the S3 object
            response = client.get_object(
                Bucket=bucket_name,
                Key=object_key
            )

            # Get the content type
            content_type = response['ContentType']

            # Stream the data
            data = response['Body'].read()

            # Get the origin from the request headers
            origin = request.headers.get('origin', '*')

            # Set appropriate CORS headers
            cors_headers = {
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Credentials": "true",
                "Cache-Control": "public, max-age=86400"  # Cache for 24 hours
            }

            # Check if origin is allowed
            allowed_origins = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app").split(",")
            allowed_origins = [o.strip() for o in allowed_origins if o.strip()]
            if os.getenv("ENVIRONMENT") == "development":
                allowed_origins.append("http://localhost:3000")

            # Set Access-Control-Allow-Origin
            if origin in allowed_origins or "*" in allowed_origins:
                cors_headers["Access-Control-Allow-Origin"] = origin
            elif origin != "unknown":
                # If we have an origin but it's not allowed, use the first allowed origin
                # This might help in some cases where the domain is the same but with different subdomains
                if allowed_origins:
                    cors_headers["Access-Control-Allow-Origin"] = allowed_origins[0]
                    logger.warning(f"Origin {origin} not allowed, using {allowed_origins[0]} instead")
                else:
                    cors_headers["Access-Control-Allow-Origin"] = "https://photo-share-app-id.web.app"
                    logger.warning(f"No allowed origins found, using default")
            else:
                # If no origin, use wildcard for testing
                cors_headers["Access-Control-Allow-Origin"] = "*"
                logger.warning(f"No origin found, using wildcard")

            # Return with appropriate content type and CORS headers
            return Response(
                content=data,
                media_type=content_type,
                headers=cors_headers
            )

        except botocore.exceptions.ClientError as e:
            error_code = e.response['Error']['Code']
            origin = request.headers.get('origin', '*')

            # Create consistent CORS headers for error responses
            allowed_origins = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app").split(",")
            allowed_origins = [o.strip() for o in allowed_origins if o.strip()]
            if os.getenv("ENVIRONMENT") == "development":
                allowed_origins.append("http://localhost:3000")

            cors_headers = {
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Credentials": "true",
            }

            if origin in allowed_origins or "*" in allowed_origins:
                cors_headers["Access-Control-Allow-Origin"] = origin
            elif origin != "unknown" and allowed_origins:
                cors_headers["Access-Control-Allow-Origin"] = allowed_origins[0]
            else:
                cors_headers["Access-Control-Allow-Origin"] = "*"

            if error_code == 'NoSuchKey':
                logger.error(f"S3 object not found: {bucket_name}/{object_key}")
                return JSONResponse(
                    status_code=404,
                    content={"detail": "Image not found in S3"},
                    headers=cors_headers
                )
            elif error_code == 'AccessDenied':
                logger.error(f"Access denied to S3 object: {bucket_name}/{object_key}")
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Access denied to the requested image"},
                    headers=cors_headers
                )
            else:
                logger.error(f"S3 error: {error_code} - {str(e)}")
                return JSONResponse(
                    status_code=500,
                    content={"detail": f"S3 error: {error_code}"},
                    headers=cors_headers
                )

    except Exception as e:
        logger.error(f"Error proxying image: {str(e)}")
        origin = request.headers.get('origin', '*')

        # Create consistent CORS headers for general error response
        allowed_origins = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app").split(",")
        allowed_origins = [o.strip() for o in allowed_origins if o.strip()]
        if os.getenv("ENVIRONMENT") == "development":
            allowed_origins.append("http://localhost:3000")

        cors_headers = {
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Credentials": "true",
        }

        if origin in allowed_origins or "*" in allowed_origins:
            cors_headers["Access-Control-Allow-Origin"] = origin
        elif origin != "unknown" and allowed_origins:
            cors_headers["Access-Control-Allow-Origin"] = allowed_origins[0]
        else:
            cors_headers["Access-Control-Allow-Origin"] = "*"

        return JSONResponse(
            status_code=500,
            content={"detail": f"Failed to proxy image: {str(e)}"},
            headers=cors_headers
        )

@router.options("/direct-access")
async def direct_access_options(request: Request):
    """Handle OPTIONS requests for CORS preflight checks."""
    origin = request.headers.get('origin', '*')

    # Check if origin is allowed
    allowed_origins = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app").split(",")
    allowed_origins = [o.strip() for o in allowed_origins if o.strip()]
    if os.getenv("ENVIRONMENT") == "development":
        allowed_origins.append("http://localhost:3000")

    # Create CORS headers
    cors_headers = {
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "*",
        "Access-Control-Allow-Credentials": "true",
        "Access-Control-Max-Age": "3600",
    }

    # Set Access-Control-Allow-Origin
    if origin in allowed_origins or "*" in allowed_origins:
        cors_headers["Access-Control-Allow-Origin"] = origin
    elif origin != "unknown":
        if allowed_origins:
            cors_headers["Access-Control-Allow-Origin"] = allowed_origins[0]
            logger.warning(f"OPTIONS: Origin {origin} not allowed, using {allowed_origins[0]} instead")
        else:
            cors_headers["Access-Control-Allow-Origin"] = "https://photo-share-app-id.web.app"
            logger.warning(f"OPTIONS: No allowed origins found, using default")
    else:
        cors_headers["Access-Control-Allow-Origin"] = "*"
        logger.warning(f"OPTIONS: No origin found, using wildcard")

    return Response(
        content="",
        headers=cors_headers
    )

# Add new model for proxy upload request
class ProxyUploadRequest(BaseModel):
    presigned_url: str
    file_content: str  # Base64 encoded file content

@router.post("/proxy-upload")
async def proxy_upload(
    request: ProxyUploadRequest,
    s3_client = Depends(get_s3_client)
):
    """
    Proxy endpoint to help web clients bypass CORS restrictions when uploading to S3.
    Takes a presigned URL and base64-encoded file content, then uploads the file to S3.
    """
    try:
        logger.info("Received proxy upload request")

        # Parse the URL to extract important information
        parsed_url = urlparse(request.presigned_url)

        # Decode the base64 file content
        try:
            file_content = base64.b64decode(request.file_content)
        except Exception as e:
            logger.error(f"Failed to decode base64 content: {e}")
            raise HTTPException(
                status_code=400,
                detail=f"Invalid base64 encoding: {str(e)}"
            )

        # Create a file-like object from the decoded content
        file_obj = io.BytesIO(file_content)

        # Make the request to S3 using the presigned URL
        async with httpx.AsyncClient() as client:
            # Extract content type from presigned URL query parameters if available
            query_params = parse_qs(parsed_url.query)
            content_type = "image/jpeg"  # Default content type

            if "Content-Type" in query_params:
                content_type = query_params["Content-Type"][0]

            # Make the PUT request to S3
            response = await client.put(
                request.presigned_url,
                content=file_content,
                headers={"Content-Type": content_type}
            )

            if response.status_code not in [200, 204]:
                logger.error(f"S3 upload failed: {response.status_code} - {response.text}")
                raise HTTPException(
                    status_code=response.status_code,
                    detail=f"S3 upload failed: {response.text}"
                )

        return {"success": True, "message": "File uploaded successfully via proxy"}

    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except ClientError as e:
        error_response = e.response.get('Error', {})
        error_code = error_response.get('Code', 'Unknown')
        error_message = error_response.get('Message', str(e))
        logger.error(f"S3 ClientError in proxy upload: {error_code} - {error_message}")
        raise HTTPException(
            status_code=500,
            detail=f"S3 error: {error_code} - {error_message}"
        )
    except Exception as e:
        logger.error(f"Unexpected error in proxy upload: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Proxy upload failed: {str(e)}"
        )