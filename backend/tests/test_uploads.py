import pytest
import boto3
from moto import mock_aws
from fastapi.testclient import TestClient
from app.main import app
from app.api.uploads import BUCKET_NAME
from app.services.dynamodb import UPLOAD_PARTS_TABLE


@pytest.fixture
def aws_ctx():
    """Fixture that creates mocked S3 + DynamoDB and a TestClient inside the mock context."""
    with mock_aws():
        s3 = boto3.client('s3', region_name='ap-south-1')
        s3.create_bucket(
            Bucket=BUCKET_NAME,
            CreateBucketConfiguration={'LocationConstraint': 'ap-south-1'},
        )
        ddb = boto3.resource('dynamodb', region_name='ap-south-1')
        ddb.create_table(
            TableName=UPLOAD_PARTS_TABLE,
            KeySchema=[{'AttributeName': 'upload_id', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'upload_id', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST',
        )
        with TestClient(app) as client:
            yield {'s3': s3, 'dynamodb': ddb, 'client': client}


def test_generate_multipart_upload_stores_key_in_dynamodb(aws_ctx):
    resp = aws_ctx['client'].post('/api/v1/generate-multipart-upload-urls', json={
        'event_id': 'evt-1',
        'file_names': ['photo.jpg'],
    })
    assert resp.status_code == 200
    config = resp.json()['upload_configs'][0]
    upload_id = config['upload_id']
    file_key = config['file_key']

    table = aws_ctx['dynamodb'].Table(UPLOAD_PARTS_TABLE)
    item = table.get_item(Key={'upload_id': upload_id}).get('Item')
    assert item is not None
    assert item['file_key'] == file_key
    assert item['event_id'] == 'evt-1'
    assert 'ttl' in item
