from pydantic import BaseModel
from typing import List

class PasswordAuth(BaseModel):
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str

class PhotoList(BaseModel):
    photos: List[str]

class SelectionResponse(BaseModel):
    success: bool
    message: str
