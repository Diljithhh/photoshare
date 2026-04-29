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


def test_get_presigned_part_url_uses_dynamodb_lookup(aws_ctx):
    # Seed DynamoDB with a known mapping (bypassing the initiate endpoint)
    file_key = 'evt-1/some-uuid/photo.jpg'
    fake_upload_id = 'fake-upload-id-abc'
    table = aws_ctx['dynamodb'].Table(UPLOAD_PARTS_TABLE)
    table.put_item(Item={
        'upload_id': fake_upload_id,
        'file_key': file_key,
        'event_id': 'evt-1',
        'ttl': 9999999999,
    })

    resp = aws_ctx['client'].post('/api/v1/get-presigned-upload-part-url', json={
        'event_id': 'evt-1',
        'file_name': 'photo.jpg',
        'upload_id': fake_upload_id,
        'part_number': 1,
    })
    assert resp.status_code == 200
    assert 'presigned_url' in resp.json()


def test_get_presigned_part_url_returns_404_when_upload_not_found(aws_ctx):
    resp = aws_ctx['client'].post('/api/v1/get-presigned-upload-part-url', json={
        'event_id': 'evt-1',
        'file_name': 'photo.jpg',
        'upload_id': 'does-not-exist',
        'part_number': 1,
    })
    assert resp.status_code == 404


def test_complete_multipart_upload_uses_dynamodb_lookup(aws_ctx):
    # Create a real multipart upload in mock S3
    s3 = aws_ctx['s3']
    file_key = 'evt-1/some-uuid/photo.jpg'
    mp = s3.create_multipart_upload(Bucket=BUCKET_NAME, Key=file_key)
    upload_id = mp['UploadId']

    # Upload one part (minimum 5 MB for S3 multipart)
    part = s3.upload_part(
        Bucket=BUCKET_NAME, Key=file_key,
        UploadId=upload_id, PartNumber=1, Body=b'a' * 5 * 1024 * 1024,
    )
    etag = part['ETag'].strip('"')

    # Seed DynamoDB
    table = aws_ctx['dynamodb'].Table(UPLOAD_PARTS_TABLE)
    table.put_item(Item={
        'upload_id': upload_id,
        'file_key': file_key,
        'event_id': 'evt-1',
        'ttl': 9999999999,
    })

    resp = aws_ctx['client'].post('/api/v1/complete-multipart-upload', json={
        'event_id': 'evt-1',
        'file_name': 'photo.jpg',
        'upload_id': upload_id,
        'parts': [{'PartNumber': 1, 'ETag': etag}],
    })
    assert resp.status_code == 200
    assert 'file_url' in resp.json()


def test_complete_multipart_upload_returns_404_when_upload_not_found(aws_ctx):
    resp = aws_ctx['client'].post('/api/v1/complete-multipart-upload', json={
        'event_id': 'evt-1',
        'file_name': 'photo.jpg',
        'upload_id': 'nonexistent-upload-id',
        'parts': [{'PartNumber': 1, 'ETag': 'abc123'}],
    })
    assert resp.status_code == 404
