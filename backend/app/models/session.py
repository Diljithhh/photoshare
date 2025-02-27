from typing import List
from pydantic import BaseModel
import boto3
from botocore.exceptions import ClientError
from datetime import datetime, timedelta
import bcrypt
import secrets
import string
from app.core.config import settings
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize DynamoDB client
try:
    dynamodb = boto3.resource(
        'dynamodb',
        region_name=settings.AWS_DEFAULT_REGION,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY
    )

    # Define the table
    table = dynamodb.Table('photo_sessions')

    # Test the connection by describing the table
    try:
        table.table_status
        logger.info("Successfully connected to existing DynamoDB table")
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            logger.info("Table does not exist, creating new table...")
            table = dynamodb.create_table(
                TableName='photo_sessions',
                KeySchema=[
                    {
                        'AttributeName': 'session_id',
                        'KeyType': 'HASH'  # Partition key
                    }
                ],
                AttributeDefinitions=[
                    {
                        'AttributeName': 'session_id',
                        'AttributeType': 'S'
                    }
                ],
                ProvisionedThroughput={
                    'ReadCapacityUnits': 5,
                    'WriteCapacityUnits': 5
                }
            )
            # Wait until the table exists
            table.meta.client.get_waiter('table_exists').wait(TableName='photo_sessions')
            logger.info("Table created successfully")
        else:
            logger.error(f"Error accessing DynamoDB: {str(e)}")
            raise e

except Exception as e:
    logger.error(f"Failed to initialize DynamoDB client: {str(e)}")
    raise e

class SessionCreate(BaseModel):
    event_id: str
    photo_urls: List[str]

class SessionResponse(BaseModel):
    session_id: str
    access_link: str
    password: str

def generate_password() -> str:
    """Generate a random 6-character alphanumeric password."""
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(6))

def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode(), salt).decode()

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash."""
    return bcrypt.checkpw(
        plain_password.encode(),
        hashed_password.encode()
    )

def store_session(session_id: str, event_id: str, hashed_password: str, photo_urls: List[str]) -> bool:
    """Store session data in DynamoDB."""
    try:
        table.put_item(
            Item={
                'session_id': session_id,
                'event_id': event_id,
                'password_hash': hashed_password,
                'photo_urls': photo_urls,
                'created_at': datetime.utcnow().isoformat(),
                'expires_at': (datetime.utcnow() + timedelta(days=30)).isoformat()  # 30-day expiration
            }
        )
        return True
    except Exception as e:
        print(f"Error storing session: {str(e)}")
        return False

def get_session(session_id: str) -> dict:
    """Retrieve session data from DynamoDB."""
    try:
        response = table.get_item(
            Key={
                'session_id': session_id
            }
        )
        return response.get('Item')
    except Exception as e:
        print(f"Error retrieving session: {str(e)}")
        return None