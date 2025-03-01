import uvicorn
import logging
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler("backend_debug.log")
        ]
    )

    logger = logging.getLogger(__name__)
    logger.info("Starting local development server...")
    logger.info(f"Using DynamoDB table: photo_sessions_share")

    # Set environment variable to make it clear we're in local development
    os.environ["ENVIRONMENT"] = "development"

    # Run the server with hot reload enabled
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="debug"
    )