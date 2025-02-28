# from fastapi import FastAPI, Request
# from fastapi.middleware.cors import CORSMiddleware
# from app.core.config import settings
# from app.api.uploads import router as upload_router
# from app.api.sessions import router as session_router
# from app.core.init_aws import create_s3_bucket
# import uvicorn
# import logging
# import json
# from fastapi.concurrency import iterate_in_threadpool

# # Set up logging
# logging.basicConfig(
#     level=logging.INFO,
#     format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
# )
# logger = logging.getLogger(__name__)

# app = FastAPI(
#     title="PhotoShare API",
#     description="Backend API for PhotoShare application",
#     version="0.1.0",
# )

# # Configure CORS with more permissive settings for development
# origins = [
#     "http://localhost",
#     "http://localhost:8000",
#     "http://localhost:61962",
#     "http://127.0.0.1:61962",
#     "*"  # Remove this in production
# ]

# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=["*"],  # Adjust this in production
#     allow_credentials=True,
#     allow_methods=["*"],
#     allow_headers=["*"],
# )


# # Add logging middleware
# @app.middleware("http")
# async def log_requests(request: Request, call_next):
#     logger.info(f"Request path: {request.url.path}")
#     logger.info(f"Request method: {request.method}")
#     logger.info(f"Request headers: {request.headers}")
#     logger.info(f"Query params: {request.query_params}")

#     # Log request body
#     try:
#         body = await request.body()
#         if body:
#             try:
#                 # Try to parse as JSON for better formatting
#                 json_body = json.loads(body)
#                 logger.info(f"Request body (JSON): {json_body}")
#             except json.JSONDecodeError:
#                 # If not JSON, log as string
#                 logger.info(f"Request body (raw): {body.decode()}")
#     except Exception as e:
#         logger.error(f"Error reading request body: {e}")

#     # Store body for endpoints to access
#     request._body = body

#     response = await call_next(request)

#     # Log response details
#     logger.info(f"Response status: {response.status_code}")

#     # Log response headers
#     logger.info(f"Response headers: {response.headers}")

#     # Try to log response body for error responses
#     if response.status_code >= 400:
#         try:
#             response_body = [section async for section in response.body_iterator]
#             response.body_iterator = iterate_in_threadpool(iter(response_body))

#             body = b''.join(response_body).decode()
#             try:
#                 json_body = json.loads(body)
#                 logger.error(f"Error response body: {json_body}")
#             except json.JSONDecodeError:
#                 logger.error(f"Error response body: {body}")
#         except Exception as e:
#             logger.error(f"Error reading response body: {e}")

#     return response

# # Include routers
# app.include_router(upload_router, prefix="/api/v1", tags=["uploads"])
# app.include_router(session_router, prefix="/api/v1", tags=["sessions"])

# @app.api_route("/", methods=["GET", "HEAD"])
# async def root():
#     return {"message": "Welcome to PhotoShare API"}

# @app.on_event("startup")
# async def startup_event():
#     """Initialize AWS resources on startup"""
#     try:
#         create_s3_bucket()
#         logger.info("AWS resources initialized successfully")
#     except Exception as e:
#         logger.error(f"Failed to initialize AWS resources: {str(e)}")

# def start_server():
#     """Entry point for the server script."""
#     logger.info("Starting server...")
#     uvicorn.run(
#         "app.main:app",
#         host="0.0.0.0",
#         port=8000,
#         reload=True,
#         log_level="info"
#     )

# if __name__ == "__main__":
#     start_server()

# main.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import logging
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html

# Import the photo upload router - adjust the import path as needed
from app.api.uploads import router as photo_router

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Photo Upload API",
    description="API for uploading photos to S3",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust this in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include the photo router
# The router already has the prefix "/api/v1"
app.include_router(photo_router, tags=["photos"])

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