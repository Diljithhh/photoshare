from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.uploads import router as upload_router
from app.api.sessions import router as session_router
from app.core.init_aws import create_s3_bucket
import uvicorn
import logging
import json

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="PhotoShare API",
    description="Backend API for PhotoShare application",
    version="0.1.0",
)

# Configure CORS with more permissive settings for development
origins = [
    "http://localhost",
    "http://localhost:8000",
    "http://localhost:61962",
    "http://127.0.0.1:61962",
    "*"  # Remove this in production
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,  # Set to False when allow_origins contains "*"
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"Request path: {request.url.path}")
    logger.info(f"Request method: {request.method}")
    logger.info(f"Request headers: {request.headers}")

    try:
        body = await request.body()
        if body:
            logger.info(f"Request body: {body.decode()}")
    except Exception as e:
        logger.error(f"Error reading request body: {e}")

    response = await call_next(request)

    logger.info(f"Response status: {response.status_code}")
    return response

# Include routers
app.include_router(upload_router, prefix="/api/v1", tags=["uploads"])
app.include_router(session_router, prefix="/api/v1", tags=["sessions"])

@app.get("/")
async def root():
    return {"message": "Welcome to PhotoShare API"}

@app.on_event("startup")
async def startup_event():
    """Initialize AWS resources on startup"""
    try:
        create_s3_bucket()
        logger.info("AWS resources initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize AWS resources: {str(e)}")

def start_server():
    """Entry point for the server script."""
    logger.info("Starting server...")
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )

if __name__ == "__main__":
    start_server()