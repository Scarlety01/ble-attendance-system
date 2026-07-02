from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from typing import Callable

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

import models
from auth import decode_token
from database import SessionLocal

RATE_LIMIT_PER_MINUTE = 100
_REQUEST_LOG: dict[str, deque[datetime]] = defaultdict(deque)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def check_rate_limit(request: Request) -> None:
    client_ip = request.client.host if request.client else "unknown"
    now = datetime.now(timezone.utc)
    bucket = _REQUEST_LOG[client_ip]
    limit_time = now - timedelta(minutes=1)

    while bucket and bucket[0] < limit_time:
        bucket.popleft()

    if len(bucket) >= RATE_LIMIT_PER_MINUTE:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    bucket.append(now)


def get_current_user(
    authorization: str = Header(default=None),
    db: Session = Depends(get_db),
):
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header missing")

    parts = authorization.split(" ")
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid authorization format")

    payload = decode_token(parts[1])
    if not payload or payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Invalid or expired access token")

    user_id = payload.get("sub")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="User is inactive")

    return user


def require_roles(*roles: str) -> Callable:
    def checker(current_user=Depends(get_current_user)):
        if current_user.role not in roles:
            raise HTTPException(status_code=403, detail="Access denied")
        return current_user

    return checker


def ensure_same_org(current_user, organization_id: str) -> None:
    if current_user.organization_id != organization_id:
        raise HTTPException(status_code=403, detail="Cross-organization access denied")
