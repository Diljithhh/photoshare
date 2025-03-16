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
import boto3
from pydantic import BaseModel
from pydantic_settings import BaseSettings
from urllib.parse import urlparse

# Import the photo upload router - adjust the import path as needed
from app.api.uploads import router as photo_router

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Function to get the base domain from a URL (for CORS comparison)
def get_domain_from_url(url):
    """Extract just the base domain from a URL for CORS comparison."""
    try:
        parsed = urlparse(url)
        return f"{parsed.scheme}://{parsed.netloc}"
    except:
        return url

# Configuration class
class Settings(BaseSettings):
    AWS_ACCESS_KEY_ID: str = os.getenv("AWS_ACCESS_KEY_ID", "")
    AWS_SECRET_ACCESS_KEY: str = os.getenv("AWS_SECRET_ACCESS_KEY", "")
    AWS_DEFAULT_REGION: str = os.getenv("AWS_DEFAULT_REGION", "ap-south-1")
    AWS_BUCKET_NAME: str = "screenmirror-canvas-storage"
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "production")
    ALLOWED_ORIGINS: str = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app")

    class Config:
        env_file = ".env"
        extra = "allow"

app = FastAPI(
    title="Photo Upload API",
    description="API for uploading photos to S3",
    version="1.0.0"
)

# Get allowed origins from environment variable and extract just the domains
allowed_origin_strings = os.getenv("ALLOWED_ORIGINS", "https://photo-share-app-id.web.app").split(",")
allowed_origins = [get_domain_from_url(origin.strip()) for origin in allowed_origin_strings if origin.strip()]

# In development, add localhost
if os.getenv("ENVIRONMENT") == "development":
    allowed_origins.append("http://localhost:3000")

# For testing or debugging, uncomment to allow all origins
# allowed_origins.append("*")

print(f"CORS allowed origins: {allowed_origins}")

# Save the allowed domains for use in middleware
app.state.allowed_domains = allowed_origins

# Add custom middleware to handle CORS with dynamic session-based URLs
@app.middleware("http")
async def cors_middleware(request: Request, call_next):
    # Get the request origin
    origin = request.headers.get("origin")

    # If no origin, just pass through
    if not origin:
        return await call_next(request)

    # Extract just the domain from origin
    origin_domain = get_domain_from_url(origin)

    # Store the full origin and its domain in request state for use in the endpoint
    request.state.origin = origin
    request.state.origin_domain = origin_domain
    request.state.allowed_domains = app.state.allowed_domains

    # Process the request
    response = await call_next(request)

    # If we have an origin, check if its domain is allowed
    if origin_domain in app.state.allowed_domains or "*" in app.state.allowed_domains:
        # If domain is allowed, set full origin as allowed
        response.headers["Access-Control-Allow-Origin"] = origin
    elif app.state.allowed_domains:
        # If domain is not allowed but we have allowed domains, use first one
        response.headers["Access-Control-Allow-Origin"] = app.state.allowed_domains[0]
    else:
        # Fallback to wildcard
        response.headers["Access-Control-Allow-Origin"] = "*"

    # Add other CORS headers
    response.headers["Access-Control-Allow-Credentials"] = "true"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "*"

    return response

# Add startup event to initialize app state
@app.on_event("startup")
async def startup_event():
    logger.info("Initializing application state...")
    # Create and store settings
    app.state.config = Settings()

    # Initialize S3 client
    app.state.s3_client = boto3.client(
        's3',
        region_name=app.state.config.AWS_DEFAULT_REGION,
        aws_access_key_id=app.state.config.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=app.state.config.AWS_SECRET_ACCESS_KEY
    )

    logger.info(f"Application initialized in {app.state.config.ENVIRONMENT} mode")
    logger.info(f"Using AWS region: {app.state.config.AWS_DEFAULT_REGION}")

# Add CORS middleware - only used as fallback, our custom middleware handles most cases
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins + ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Type", "Content-Length", "Content-Disposition"],
    max_age=3600,
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