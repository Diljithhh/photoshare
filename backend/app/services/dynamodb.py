import boto3
import os
import time
from botocore.exceptions import ClientError
from dotenv import load_dotenv

load_dotenv()

UPLOAD_PARTS_TABLE = 'upload_parts'
_TTL_SECONDS = 86400  # 24 hours


def get_dynamodb_client():
    return boto3.resource(
        'dynamodb',
        region_name='ap-south-1',
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
    )


def save_upload_key(upload_id: str, file_key: str, event_id: str) -> None:
    dynamodb = get_dynamodb_client()
    table = dynamodb.Table(UPLOAD_PARTS_TABLE)
    table.put_item(Item={
        'upload_id': upload_id,
        'file_key': file_key,
        'event_id': event_id,
        'ttl': int(time.time()) + _TTL_SECONDS,
    })


def get_file_key_for_upload(upload_id: str) -> str | None:
    dynamodb = get_dynamodb_client()
    table = dynamodb.Table(UPLOAD_PARTS_TABLE)
    result = table.get_item(Key={'upload_id': upload_id})
    item = result.get('Item')
    return item['file_key'] if item else None


def ensure_upload_parts_table_exists() -> None:
    dynamodb = get_dynamodb_client()
    try:
        dynamodb.create_table(
            TableName=UPLOAD_PARTS_TABLE,
            KeySchema=[{'AttributeName': 'upload_id', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'upload_id', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST',
        )
    except ClientError as e:
        if e.response['Error']['Code'] != 'ResourceInUseException':
            raise

    # Enable TTL (DynamoDB raises ValidationException if already enabled — that's fine)
    client = dynamodb.meta.client
    try:
        client.update_time_to_live(
            TableName=UPLOAD_PARTS_TABLE,
            TimeToLiveSpecification={'Enabled': True, 'AttributeName': 'ttl'},
        )
    except ClientError as e:
        if e.response['Error']['Code'] != 'ValidationException':
            raise
