# main.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import logging
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from app.api.sessions import router as session_router
from app.api.jwt import router as jwt_router
import os
from dotenv import load_dotenv

# Import the photo upload router - adjust the import path as needed
from app.api.uploads import router as photo_router

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

app = FastAPI(
    title="Photo Upload API",
    description="API for uploading photos to S3",
    version="1.0.0"
)

# Get allowed origins from environment variable
allowed_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:8000").split(",")
# For local development, add any frontend origin
if os.getenv("ENVIRONMENT") == "development":
    allowed_origins = ["*"]  # Allow all origins in development
print(f"CORS allowed origins: {allowed_origins}")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include the photo router
# The router already has the prefix "/api/v1"
app.include_router(photo_router, tags=["photos"])
app.include_router(session_router, tags=["sessions"])
app.include_router(jwt_router, tags=["jwt"])


# Middleware for logging requests and handling errors
@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"Request path: {request.url.path}")
    logger.info(f"Request method: {request.method}")
    logger.info(f"Request headers: {request.headers}")
    logger.info(f"Query params: {request.query_params}")

    try:
        response = await call_next(request)
        logger.info(f"Response status: {response.status_code}")
        logger.info(f"Response headers: {response.headers}")
        return response
    except Exception as e:
        logger.error(f"Error in middleware: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={"detail": f"Internal Server Error: {str(e)}"}
        )

@app.get("/")
async def root():
    """Root endpoint"""
    return {"message": "Welcome to the Photo Upload API. Go to /docs for the API documentation."}

# For testing the S3 connection
@app.get("/api/v1/test-s3-connection")
async def test_s3_connection():
    """Test S3 connection"""
    import boto3
    from botocore.exceptions import ClientError
    import os

    try:
        s3_client = boto3.client(
            's3',
            region_name='ap-south-1',
            aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
            aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
        )

        # List buckets to test connection
        response = s3_client.list_buckets()
        buckets = [bucket['Name'] for bucket in response['Buckets']]

        return {
            "success": True,
            "message": "Successfully connected to S3",
            "buckets": buckets
        }
    except ClientError as e:
        return {
            "success": False,
            "message": f"Error connecting to S3: {str(e)}"
        }
    except Exception as e:
        return {
            "success": False,
            "message": f"Unexpected error: {str(e)}"
        }