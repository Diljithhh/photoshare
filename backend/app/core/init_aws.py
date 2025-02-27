import boto3
from botocore.exceptions import ClientError
import logging
from app.core.config import settings

logger = logging.getLogger(__name__)

def create_s3_bucket():
    """Create S3 bucket if it doesn't exist"""
    s3_client = boto3.client(
        's3',
        region_name=settings.AWS_DEFAULT_REGION,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY
    )

    BUCKET_NAME = "screenmirror-canvas-storage"

    try:
        s3_client.head_bucket(Bucket=BUCKET_NAME)
        logger.info(f"Bucket {BUCKET_NAME} already exists")
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == '404':
            # Bucket doesn't exist, create it
            try:
                s3_client.create_bucket(
                    Bucket=BUCKET_NAME,
                    CreateBucketConfiguration={
                        'LocationConstraint': settings.AWS_DEFAULT_REGION
                    }
                )

                # Configure CORS for the bucket with broader permissions for web uploads
                cors_configuration = {
                    'CORSRules': [{
                        'AllowedHeaders': [
                            '*',
                            'Content-Type',
                            'Content-Length',
                            'Access-Control-Allow-Origin',
                            'Access-Control-Allow-Methods',
                            'Access-Control-Allow-Headers'
                        ],
                        'AllowedMethods': ['GET', 'PUT', 'POST', 'DELETE', 'HEAD', 'OPTIONS'],
                        'AllowedOrigins': ['*'],
                        'ExposeHeaders': [
                            'ETag',
                            'x-amz-server-side-encryption',
                            'x-amz-request-id',
                            'x-amz-id-2',
                            'Content-Type',
                            'Content-Length'
                        ],
                        'MaxAgeSeconds': 3600
                    }]
                }

                s3_client.put_bucket_cors(
                    Bucket=BUCKET_NAME,
                    CORSConfiguration=cors_configuration
                )

                logger.info(f"Successfully created bucket {BUCKET_NAME} and configured CORS")
            except ClientError as e:
                logger.error(f"Failed to create bucket: {str(e)}")
                raise e
        else:
            logger.error(f"Error checking bucket: {str(e)}")
            raise e

    # Update CORS configuration even if bucket exists
    try:
        cors_configuration = {
            'CORSRules': [{
                'AllowedHeaders': [
                    '*',
                    'Content-Type',
                    'Content-Length',
                    'Access-Control-Allow-Origin',
                    'Access-Control-Allow-Methods',
                    'Access-Control-Allow-Headers'
                ],
                'AllowedMethods': ['GET', 'PUT', 'POST', 'DELETE', 'HEAD', 'OPTIONS'],
                'AllowedOrigins': ['*'],
                'ExposeHeaders': [
                    'ETag',
                    'x-amz-server-side-encryption',
                    'x-amz-request-id',
                    'x-amz-id-2',
                    'Content-Type',
                    'Content-Length'
                ],
                'MaxAgeSeconds': 3600
            }]
        }
        s3_client.put_bucket_cors(
            Bucket=BUCKET_NAME,
            CORSConfiguration=cors_configuration
        )
        logger.info("Updated bucket CORS configuration")
    except ClientError as e:
        logger.error(f"Failed to update bucket CORS: {str(e)}")
        raise e

if __name__ == "__main__":
    create_s3_bucket()