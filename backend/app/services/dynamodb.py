import boto3
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def get_dynamodb_client():
    """
    Get a DynamoDB client with AWS credentials from environment variables
    """
    return boto3.resource(
        'dynamodb',
        region_name='ap-south-1',
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
    )