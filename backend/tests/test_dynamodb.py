import pytest
import boto3
from moto import mock_aws
from app.services.dynamodb import (
    save_upload_key,
    get_file_key_for_upload,
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
    save_upload_key('uid-123', 'event1/fileid/photo.jpg', 'event1')
    result = get_file_key_for_upload('uid-123')
    assert result == 'event1/fileid/photo.jpg'


def test_get_file_key_returns_none_for_missing_id(dynamodb_setup):
    result = get_file_key_for_upload('nonexistent-id')
    assert result is None
