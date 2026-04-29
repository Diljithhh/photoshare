import pytest
import boto3
from moto import mock_aws
from app.services.dynamodb import (
    save_upload_key,
    get_file_key_for_upload,
    ensure_upload_parts_table_exists,
    UPLOAD_PARTS_TABLE,
)


@pytest.fixture
def dynamodb_setup():
    with mock_aws():
        resource = boto3.resource('dynamodb', region_name='ap-south-1')
        resource.create_table(
            TableName=UPLOAD_PARTS_TABLE,
            KeySchema=[{'AttributeName': 'upload_id', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'upload_id', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST',
        )
        yield resource


def test_save_and_retrieve_upload_key(dynamodb_setup):
    import time
    before = int(time.time())
    save_upload_key('uid-123', 'event1/fileid/photo.jpg', 'event1')
    result = get_file_key_for_upload('uid-123')
    assert result == 'event1/fileid/photo.jpg'

    # Verify full item
    item = dynamodb_setup.Table(UPLOAD_PARTS_TABLE).get_item(
        Key={'upload_id': 'uid-123'}
    )['Item']
    assert item['event_id'] == 'event1'
    assert item['ttl'] >= before + 86000  # ~24 hours


def test_get_file_key_returns_none_for_missing_id(dynamodb_setup):
    result = get_file_key_for_upload('nonexistent-id')
    assert result is None


def test_ensure_upload_parts_table_idempotent():
    """Calling ensure_upload_parts_table_exists twice should not raise."""
    with mock_aws():
        ensure_upload_parts_table_exists()
        ensure_upload_parts_table_exists()  # second call must not raise
