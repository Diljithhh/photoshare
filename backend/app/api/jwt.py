from fastapi import APIRouter, HTTPException, Depends, Path, status
from fastapi.security import OAuth2PasswordBearer
from app.services.jwt import create_access_token, get_current_session, verify_password
from app.models.imageview import PasswordAuth, Token, PhotoList, SelectionResponse
from app.services.dynamodb import get_dynamodb_client

from app.core.jwt import TABLE_NAME, ACCESS_TOKEN_EXPIRE_MINUTES

from datetime import datetime, timedelta

import logging
import bcrypt

logger = logging.getLogger(__name__)



router = APIRouter()






@router.post("/session/{session_id}/auth", response_model=Token)
async def authenticate_session(
    session_id: str = Path(...),
    auth_data: PasswordAuth = None,
    dynamodb = Depends(get_dynamodb_client)
):
    """
    Authenticate a user for a specific session using a password
    """
    if not auth_data:
        raise HTTPException(status_code=400, detail="Password is required")

    try:
        # Get the session from DynamoDB
        table = dynamodb.Table(TABLE_NAME)
        response = table.get_item(Key={"session_id": session_id})

        if "Item" not in response:
            raise HTTPException(status_code=404, detail="Session not found")

        session = response["Item"]

        # Verify the password
        if not verify_password(auth_data.password, session["hashed_password"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect password"
            )

        # Generate access token
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"sub": session_id},
            expires_delta=access_token_expires
        )

        return {"access_token": access_token, "token_type": "bearer"}

    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        raise HTTPException(status_code=500, detail="Database error")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Authentication failed: {str(e)}")

@router.get("/session/{session_id}/photos", response_model=PhotoList)
async def get_session_photos(
    session_id: str = Path(...),
    current_session: str = Depends(get_current_session),
    dynamodb = Depends(get_dynamodb_client)
):
    """
    Get the list of photos for a specific session (protected by JWT)
    """
    # Verify that the token session matches the requested session
    if current_session != session_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied to this session"
        )

    try:
        # Get the session from DynamoDB
        table = dynamodb.Table(TABLE_NAME)
        response = table.get_item(Key={"session_id": session_id})

        if "Item" not in response:
            raise HTTPException(status_code=404, detail="Session not found")

        session = response["Item"]

        # Return the photo URLs
        return {"photos": session.get("photo_urls", [])}

    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        raise HTTPException(status_code=500, detail="Database error")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve photos: {str(e)}")

@router.post("/session/{session_id}/select", response_model=SelectionResponse)
async def select_session_photos(
    selection: PhotoList,
    session_id: str = Path(...),
    current_session: str = Depends(get_current_session),
    dynamodb = Depends(get_dynamodb_client)
):
    """
    Save the selected photos for a specific session (protected by JWT)
    """
    # Verify that the token session matches the requested session
    if current_session != session_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied to this session"
        )

    try:
        # Get the session from DynamoDB
        table = dynamodb.Table(TABLE_NAME)
        response = table.get_item(Key={"session_id": session_id})

        if "Item" not in response:
            raise HTTPException(status_code=404, detail="Session not found")

        session = response["Item"]

        # Verify that all selected photos exist in the session
        all_photos = set(session.get("photo_urls", []))
        selected_photos = set(selection.photos)

        if not selected_photos.issubset(all_photos):
            raise HTTPException(
                status_code=400,
                detail="Selected photos contain URLs that don't exist in this session"
            )

        # Update the session with selected photos
        table.update_item(
            Key={"session_id": session_id},
            UpdateExpression="SET selected_photos = :selected, updated_at = :time",
            ExpressionAttributeValues={
                ":selected": list(selected_photos),
                ":time": int(datetime.now().timestamp())
            }
        )

        return {
            "success": True,
            "message": f"Successfully selected {len(selected_photos)} photos"
        }

    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        raise HTTPException(status_code=500, detail="Database error")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to save selection: {str(e)}")
