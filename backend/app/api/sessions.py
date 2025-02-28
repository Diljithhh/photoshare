from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List
from app.models.session import (
    SessionCreate,
    SessionResponse,
    generate_password,
    get_session,
    store_session,
    update_session_selections
)
from app.core.security import (
    create_access_token,
    verify_password,
    verify_token,
    get_password_hash
)
import uuid

router = APIRouter()

BASE_URL = "http://localhost:3000"  # Development URL for Flutter web

class AuthRequest(BaseModel):
    password: str

class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class PhotoSelectionRequest(BaseModel):
    selected_urls: List[str]

class PhotoListResponse(BaseModel):
    photos: List[str]

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
        password_hash = get_password_hash(password)

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

@router.post("/session/{session_id}/auth", response_model=AuthResponse)
async def authenticate_session(session_id: str, auth_request: AuthRequest):
    """Authenticate a session with password and return JWT token."""
    try:
        # Get session data from DynamoDB
        session = get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        # Verify password
        if not verify_password(auth_request.password, session["password_hash"]):
            raise HTTPException(status_code=401, detail="Invalid password")

        # Create access token
        access_token = create_access_token({"session_id": session_id})
        return AuthResponse(access_token=access_token)

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"An unexpected error occurred: {str(e)}"
        )

@router.get("/session/{session_id}/photos", response_model=PhotoListResponse)
async def get_session_photos(
    session_id: str,
    token_data: dict = Depends(verify_token)
):
    """Get list of photos for a session (requires authentication)."""
    try:
        # Verify session ID from token matches requested session
        if token_data["session_id"] != session_id:
            raise HTTPException(status_code=403, detail="Access denied")

        # Get session data
        session = get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        return PhotoListResponse(photos=session["photo_urls"])

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"An unexpected error occurred: {str(e)}"
        )

@router.post("/session/{session_id}/select")
async def select_photos(
    session_id: str,
    selection: PhotoSelectionRequest,
    token_data: dict = Depends(verify_token)
):
    """Update selected photos for a session (requires authentication)."""
    try:
        # Verify session ID from token matches requested session
        if token_data["session_id"] != session_id:
            raise HTTPException(status_code=403, detail="Access denied")

        # Get session data
        session = get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        # Verify all selected URLs exist in the session
        if not all(url in session["photo_urls"] for url in selection.selected_urls):
            raise HTTPException(
                status_code=400,
                detail="Selected photos must be from the session"
            )

        # Update selections in DynamoDB
        success = update_session_selections(session_id, selection.selected_urls)
        if not success:
            raise HTTPException(
                status_code=500,
                detail="Failed to update selections"
            )

        return {"message": "Selections updated successfully"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"An unexpected error occurred: {str(e)}"
        )