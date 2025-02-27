from fastapi import APIRouter, HTTPException
from app.models.session import (
    SessionCreate,
    SessionResponse,
    generate_password,
    hash_password,
    store_session
)
import uuid

router = APIRouter()

BASE_URL = "https://yourapp.com"  # Replace with your actual frontend URL

@router.post("/session/create", response_model=SessionResponse)
async def create_session(request: SessionCreate) -> SessionResponse:
    """
    Create a new photo session with password protection.

    Args:
        request: SessionCreate object containing event_id and photo_urls

    Returns:
        SessionResponse object containing session_id, access_link, and password

    Raises:
        HTTPException: If session creation fails
    """
    try:
        # Generate session ID and password
        session_id = str(uuid.uuid4())
        password = generate_password()

        # Hash the password
        password_hash = hash_password(password)

        # Store session data in DynamoDB
        success = store_session(
            session_id=session_id,
            event_id=request.event_id,
            hashed_password=password_hash,
            photo_urls=request.photo_urls
        )

        if not success:
            raise HTTPException(
                status_code=500,
                detail="Failed to create session"
            )

        # Generate access link
        access_link = f"{BASE_URL}/session/{session_id}"

        return SessionResponse(
            session_id=session_id,
            access_link=access_link,
            password=password
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"An unexpected error occurred: {str(e)}"
        )