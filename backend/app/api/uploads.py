from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import boto3
from botocore.exceptions import ClientError
import uuid
from typing import List
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize router
router = APIRouter()

# Initialize S3 client
s3_client = boto3.client(
    's3',
    region_name='ap-south-1',  # Mumbai region
    aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
)

# Constants
BUCKET_NAME = "screenmirror-canvas-storage"
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
    try:
        # Generate a unique session ID
        session_id = str(uuid.uuid4())

        # Generate presigned URLs for the requested number of photos
        presigned_urls = []
        for i in range(request.num_photos):
            # Create a unique key for each potential photo
            file_key = f"{request.event_id}/{session_id}/{i}.jpg"

            try:
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
                presigned_urls.append(presigned_url)

            except ClientError as e:
                raise HTTPException(
                    status_code=500,
                    detail=f"Error generating presigned URL: {str(e)}"
                )

        return PresignedURLResponse(
            session_id=session_id,
            presigned_urls=presigned_urls
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"An unexpected error occurred: {str(e)}"
        )