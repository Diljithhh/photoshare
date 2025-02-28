
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
    return boto3.client(
        's3',
        region_name='ap-south-1',  # Mumbai region
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

    for file in files:
        try:
            if not file.filename:
                errors.append({"error": "Empty filename"})
                continue

            # Create a unique key for the file
            file_key = f"{event_id}/{session_id}/{file.filename}"

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

            results.append({
                "filename": file.filename,
                "file_key": file_key,
                "file_url": file_url
            })
        except Exception as e:
            logger.error(f"Error uploading file {file.filename}: {str(e)}")
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

#  # photo_upload.py

# from fastapi import APIRouter, File, UploadFile, Form, HTTPException, Depends
# import boto3
# from botocore.exceptions import ClientError
# import uuid
# from typing import List
# import os
# from dotenv import load_dotenv
# import logging
# import io

# # Load environment variables
# load_dotenv()

# # Initialize router with prefix to prevent duplication
# router = APIRouter(prefix="/api/v1")

# logger = logging.getLogger(__name__)

# BUCKET_NAME = "screenmirror-canvas-storage"

# # Initialize S3 client as a dependency
# def get_s3_client():
#     return boto3.client(
#         's3',
#         region_name='ap-south-1',
#         aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
#         aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
#     )

# @router.post("/upload-photo")
# async def upload_photo(
#     event_id: str = Form(...),
#     file: UploadFile = File(...),
#     s3_client = Depends(get_s3_client)
# ):
#     """
#     Upload a single photo directly to S3 bucket
#     """
#     logger.info(f"Processing upload for event_id: {event_id}, filename: {file.filename}")

#     if not file.filename:
#         raise HTTPException(status_code=400, detail="Empty filename")

#     try:
#         # Generate a unique ID for the file
#         file_id = str(uuid.uuid4())

#         # Create a unique key for the file
#         file_key = f"{event_id}/{file_id}/{file.filename}"
#         logger.info(f"Generated S3 key: {file_key}")

#         # Create a BytesIO object from the file content
#         file_object = io.BytesIO(await file.read())

#         # Upload to S3 using the file object
#         logger.info(f"Uploading file to S3: {file_key}")
#         s3_client.upload_fileobj(
#             file_object,
#             BUCKET_NAME,
#             file_key,
#             ExtraArgs={
#                 "ContentType": file.content_type
#             }
#         )
#         logger.info(f"Successfully uploaded file to S3: {file_key}")

#         # Generate a URL to access the file (if public)
#         file_url = f"https://{BUCKET_NAME}.s3.ap-south-1.amazonaws.com/{file_key}"

#         return {
#             "success": True,
#             "file_id": file_id,
#             "file_key": file_key,
#             "file_url": file_url
#         }

#     except ClientError as e:
#         error_message = str(e)
#         logger.error(f"S3 ClientError while uploading file: {error_message}")
#         raise HTTPException(status_code=500, detail=f"Error uploading file: {error_message}")
#     except Exception as e:
#         logger.error(f"Unexpected error in upload_photo: {str(e)}")
#         raise HTTPException(status_code=500, detail=f"Failed to upload photo: {str(e)}")
#     finally:
#         await file.close()

# @router.post("/upload-multiple-photos")
# async def upload_multiple_photos(
#     event_id: str = Form(...),
#     files: List[UploadFile] = File(...),
#     s3_client = Depends(get_s3_client)
# ):
#     """
#     Upload multiple photos directly to S3 bucket
#     """
#     logger.info(f"Processing multiple uploads for event_id: {event_id}, file count: {len(files)}")

#     if not files:
#         raise HTTPException(status_code=400, detail="No files uploaded")

#     results = []
#     errors = []

#     # Generate a unique session ID for this batch
#     session_id = str(uuid.uuid4())
#     logger.info(f"Generated session_id for batch upload: {session_id}")

#     for file in files:
#         try:
#             if not file.filename:
#                 errors.append({"error": "Empty filename"})
#                 continue

#             # Create a unique key for the file
#             file_key = f"{event_id}/{session_id}/{file.filename}"

#             # Create a BytesIO object from the file content
#             file_object = io.BytesIO(await file.read())

#             # Upload to S3 using the file object
#             logger.info(f"Uploading file to S3: {file_key}")
#             s3_client.upload_fileobj(
#                 file_object,
#                 BUCKET_NAME,
#                 file_key,
#                 ExtraArgs={
#                     "ContentType": file.content_type
#                 }
#             )
#             logger.info(f"Successfully uploaded file to S3: {file_key}")

#             # Generate a URL to access the file (if public)
#             file_url = f"https://{BUCKET_NAME}.s3.ap-south-1.amazonaws.com/{file_key}"

#             results.append({
#                 "filename": file.filename,
#                 "file_key": file_key,
#                 "file_url": file_url
#             })
#         except Exception as e:
#             logger.error(f"Error uploading file {file.filename}: {str(e)}")
#             errors.append({
#                 "filename": file.filename,
#                 "error": str(e)
#             })
#         finally:
#             await file.close()

#     return {
#         "success": len(results) > 0,
#         "session_id": session_id,
#         "uploaded_files": results,
#         "errors": errors if errors else None
#     }