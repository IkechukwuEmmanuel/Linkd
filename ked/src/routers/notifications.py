"""Notifications API router — list and mark read.

All endpoints require local JWT authentication and enforce user isolation.
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import desc

from .. import models, db
from ..auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/notifications", tags=["notifications"])


def get_db():
    session = db.SessionLocal()
    try:
        yield session
    finally:
        session.close()


def _to_dict(n: models.Notification) -> dict:
    return {
        "id": n.id,
        "type": n.type,
        "title": n.title,
        "body": n.body,
        "read": n.read,
        "contact_id": n.contact_id,
        "created_at": n.created_at.isoformat() if n.created_at else None,
    }


@router.get("/")
def list_notifications(
    unread_only: bool = False,
    limit: int = 50,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """List the user's notifications (most recent first)."""
    query = db_session.query(models.Notification).filter(
        models.Notification.user_id == user_id
    )
    if unread_only:
        query = query.filter(models.Notification.read == False)  # noqa: E712
    rows = query.order_by(desc(models.Notification.created_at)).limit(limit).all()
    unread = db_session.query(models.Notification).filter(
        models.Notification.user_id == user_id,
        models.Notification.read == False,  # noqa: E712
    ).count()
    return {
        "success": True,
        "unread_count": unread,
        "data": [_to_dict(n) for n in rows],
    }


@router.post("/{notification_id}/read")
def mark_read(
    notification_id: int,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Mark a single notification as read."""
    n = db_session.query(models.Notification).filter(
        models.Notification.id == notification_id,
        models.Notification.user_id == user_id,
    ).first()
    if not n:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found"
        )
    n.read = True
    db_session.commit()
    return {"success": True, "data": _to_dict(n)}


@router.post("/read-all")
def mark_all_read(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Mark all of the user's notifications as read."""
    updated = db_session.query(models.Notification).filter(
        models.Notification.user_id == user_id,
        models.Notification.read == False,  # noqa: E712
    ).update({models.Notification.read: True})
    db_session.commit()
    return {"success": True, "updated": updated}
