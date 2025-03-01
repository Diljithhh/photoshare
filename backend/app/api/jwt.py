from fastapi import APIRouter, HTTPException, Depends, Path, status
from fastapi.security import OAuth2PasswordBearer
from app.services.jwt import create_access_token, get_current_session, verify_password
from app.models.imageview import PasswordAuth, Token, PhotoList, SelectionResponse
from app.services.dynamodb import get_dynamodb_client
from botocore.exceptions import ClientError
from fastapi.responses import JSONResponse

from app.core.jwt import TABLE_NAME, ACCESS_TOKEN_EXPIRE_MINUTES

from datetime import datetime, timedelta

import logging
import bcrypt
import traceback

logger = logging.getLogger(__name__)



router = APIRouter(prefix="/api/v1")






@router.post("/session/{session_id}/auth", response_model=Token)
async def authenticate_session(
    session_id: str = Path(...),
    auth_data: PasswordAuth = None,
    dynamodb = Depends(get_dynamodb_client)
):
    """
    Authenticate a user for a specific session using a password
    """
    # Add debug logging for the incoming request
    logger.info(f"Authentication attempt for session_id: {session_id}")
    if auth_data:
        logger.info(f"Request contains auth_data with password: {auth_data.password}")
    else:
        logger.info("Request does not contain auth_data")

    if not auth_data:
        raise HTTPException(status_code=400, detail="Password is required")

    try:
        # Get the session from DynamoDB
        table = dynamodb.Table(TABLE_NAME)
        logger.info(f"Querying DynamoDB table {TABLE_NAME} for session_id: {session_id}")
        response = table.get_item(Key={"session_id": session_id})

        if "Item" not in response:
            logger.warning(f"Session not found: {session_id}")
            # Return a 404 directly instead of throwing an exception that gets caught by the outer handler
            return JSONResponse(
                status_code=404,
                content={"detail": "Session not found"}
            )

        session = response["Item"]
        logger.info(f"Found session: {session_id}")

        # Log the stored hashed_password value
        if "hashed_password" in session:
            logger.info(f"Stored password from DynamoDB: {session['hashed_password']}")
        else:
            logger.error(f"No hashed_password found in session data: {session}")
            return JSONResponse(
                status_code=500,
                content={"detail": "Session data is missing password"}
            )

        # Verify the password
        try:
            is_valid = verify_password(auth_data.password, session["hashed_password"])
            logger.info(f"Password verification result: {is_valid}")
            if not is_valid:
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Incorrect password"}
                )
        except Exception as verify_error:
            logger.error(f"Error during password verification: {str(verify_error)}")
            return JSONResponse(
                status_code=500,
                content={"detail": f"Password verification error: {str(verify_error)}"}
            )

        # Generate access token
        logger.info("Generating JWT access token")
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"sub": session_id},
            expires_delta=access_token_expires
        )

        logger.info("Authentication successful, returning token")
        return {"access_token": access_token, "token_type": "bearer"}

    except ClientError as e:
        error_message = str(e)
        logger.error(f"DynamoDB error: {error_message}")
        return JSONResponse(
            status_code=500,
            content={"detail": f"Database error: {error_message}"}
        )
    except Exception as e:
        error_traceback = traceback.format_exc()
        logger.error(f"Unexpected error: {str(e)}")
        logger.error(f"Traceback: {error_traceback}")
        return JSONResponse(
            status_code=500,
            content={"detail": f"Authentication failed: {str(e)}"}
        )

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
