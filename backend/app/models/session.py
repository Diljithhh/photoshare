from pydantic import BaseModel
from typing import List

class CreateSessionRequest(BaseModel):
    event_id: str
    photo_urls: List[str]

class SessionResponse(BaseModel):
    session_id: str
    session_link: str
    password: str
