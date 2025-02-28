import boto3
from botocore.exceptions import ClientError
import logging
from app.core.config import settings

logger = logging.getLogger(__name__)

def create_s3_bucket():
    """Create S3 bucket if it doesn't exist"""
    logger.info("Initializing S3 bucket creation/verification process")

    try:
        s3_client = boto3.client(
            's3',
            region_name=settings.AWS_DEFAULT_REGION,
            aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
            aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY
        )
        logger.info("Successfully created S3 client")

        BUCKET_NAME = "screenmirror-canvas-storage"
        logger.info(f"Checking if bucket {BUCKET_NAME} exists")

        try:
            s3_client.head_bucket(Bucket=BUCKET_NAME)
            logger.info(f"Bucket {BUCKET_NAME} already exists")
        except ClientError as e:
            error_code = e.response['Error']['Code']
            logger.info(f"Received error code {error_code} while checking bucket")

            if error_code == '404':
                # Bucket doesn't exist, create it
                logger.info(f"Bucket {BUCKET_NAME} doesn't exist, creating now...")
                try:
                    location = {'LocationConstraint': settings.AWS_DEFAULT_REGION}
                    s3_client.create_bucket(
                        Bucket=BUCKET_NAME,
                        CreateBucketConfiguration=location
                    )
                    logger.info(f"Successfully created bucket {BUCKET_NAME}")

                    # Configure CORS for the bucket
                    cors_configuration = {
                        'CORSRules': [{
                            'AllowedHeaders': ['*'],
                            'AllowedMethods': ['GET', 'PUT', 'POST', 'DELETE', 'HEAD'],
                            'AllowedOrigins': ['*'],
                            'ExposeHeaders': ['ETag'],
                            'MaxAgeSeconds': 3000
                        }]
                    }

                    s3_client.put_bucket_cors(
                        Bucket=BUCKET_NAME,
                        CORSConfiguration=cors_configuration
                    )
                    logger.info("Successfully configured CORS for the bucket")

                except ClientError as create_error:
                    error_response = create_error.response.get('Error', {})
                    error_code = error_response.get('Code', 'Unknown')
                    error_message = error_response.get('Message', str(create_error))
                    logger.error(f"Failed to create bucket: Code={error_code}, Message={error_message}")
                    raise create_error
            elif error_code == '403':
                logger.error("Access denied. Please check AWS credentials and permissions")
                raise e
            else:
                logger.error(f"Error checking bucket: {str(e)}")
                raise e

        # Update CORS configuration even if bucket exists
        try:
            cors_configuration = {
                'CORSRules': [{
                    'AllowedHeaders': ['*'],
                    'AllowedMethods': ['GET', 'PUT', 'POST', 'DELETE', 'HEAD'],
                    'AllowedOrigins': ['*'],
                    'ExposeHeaders': ['ETag'],
                    'MaxAgeSeconds': 3000
                }]
            }
            s3_client.put_bucket_cors(
                Bucket=BUCKET_NAME,
                CORSConfiguration=cors_configuration
            )
            logger.info("Updated bucket CORS configuration")
        except ClientError as cors_error:
            error_response = cors_error.response.get('Error', {})
            error_code = error_response.get('Code', 'Unknown')
            error_message = error_response.get('Message', str(cors_error))
            logger.error(f"Failed to update bucket CORS: Code={error_code}, Message={error_message}")
            raise cors_error

    except Exception as e:
        logger.error(f"Unexpected error in create_s3_bucket: {str(e)}")
        raise e

if __name__ == "__main__":
    create_s3_bucket()