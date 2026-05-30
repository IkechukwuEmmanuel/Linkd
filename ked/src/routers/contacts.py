"""Contacts API router — full CRUD, search, follow-ups, and export.

All endpoints require JWT authentication and enforce user isolation.
"""

import json
import logging
from typing import Optional, List
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, func, text, desc, asc
from pydantic import BaseModel, Field

from .. import models, db
from ..auth import get_current_user
from ..tasks.contact_tasks import create_contact_from_transcript

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/contacts", tags=["contacts"])


# ============================================================================
# Request/Response Models
# ============================================================================

class ContactCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    company: Optional[str] = None
    role: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    linkedin_url: Optional[str] = None
    event_name: Optional[str] = None
    event_date: Optional[str] = None
    interests: List[str] = []
    opportunities: List[str] = []
    summary: Optional[str] = None
    notes: Optional[str] = None
    tags: List[str] = []


class ContactUpdate(BaseModel):
    name: Optional[str] = None
    company: Optional[str] = None
    role: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    linkedin_url: Optional[str] = None
    event_name: Optional[str] = None
    interests: Optional[List[str]] = None
    opportunities: Optional[List[str]] = None
    summary: Optional[str] = None
    notes: Optional[str] = None
    tags: Optional[List[str]] = None
    is_starred: Optional[bool] = None


class QuickCaptureRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    note: str = Field(..., min_length=1)
    event_name: Optional[str] = None


# ============================================================================
# Helpers
# ============================================================================

def get_db():
    session = db.SessionLocal()
    try:
        yield session
    finally:
        session.close()


def _contact_to_dict(contact: models.Contact) -> dict:
    """Serialize Contact ORM to dict."""
    return {
        "id": contact.id,
        "user_id": contact.user_id,
        "name": contact.name,
        "company": contact.company,
        "role": contact.role,
        "email": contact.email,
        "phone": contact.phone,
        "linkedin_url": contact.linkedin_url,
        "event_name": contact.event_name,
        "event_date": contact.event_date.isoformat() if contact.event_date else None,
        "location": contact.location,
        "notes": contact.notes,
        "interests": contact.interests or [],
        "opportunities": contact.opportunities or [],
        "summary": contact.summary,
        "overlap_points": contact.overlap_points or [],
        "overlap_score": contact.overlap_score or 0.0,
        "follow_up_draft": contact.follow_up_draft,
        "follow_up_sent": contact.follow_up_sent or False,
        "follow_up_due": contact.follow_up_due.isoformat() if contact.follow_up_due else None,
        "follow_up_completed": contact.follow_up_completed or False,
        "relationship_strength": contact.relationship_strength or 1,
        "last_interaction_at": contact.last_interaction_at.isoformat() if contact.last_interaction_at else None,
        "interaction_count": contact.interaction_count or 1,
        "is_starred": contact.is_starred or False,
        "tags": contact.tags or [],
        "created_at": contact.created_at.isoformat() if contact.created_at else None,
        "updated_at": contact.updated_at.isoformat() if contact.updated_at else None,
    }


# ============================================================================
# CRUD Endpoints
# ============================================================================

@router.post("/", status_code=status.HTTP_201_CREATED)
def create_contact(
    request: ContactCreate,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Create a new contact manually."""
    try:
        contact = models.Contact(
            user_id=user_id,
            name=request.name,
            company=request.company,
            role=request.role,
            email=request.email,
            phone=request.phone,
            linkedin_url=request.linkedin_url,
            event_name=request.event_name,
            event_date=request.event_date,
            interests=request.interests,
            opportunities=request.opportunities,
            summary=request.summary,
            notes=request.notes,
            tags=request.tags,
            last_interaction_at=datetime.utcnow(),
        )
        db_session.add(contact)
        db_session.commit()
        db_session.refresh(contact)

        logger.info(f"[user_id={user_id}] Contact created: {contact.id} - {contact.name}")
        return {"success": True, "data": _contact_to_dict(contact)}

    except Exception as e:
        db_session.rollback()
        logger.error(f"[user_id={user_id}] Create contact failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to create contact")


@router.post("/from-recording/{job_id}")
def create_contact_from_recording(
    job_id: str,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Create a contact from a processed recording/job."""
    job = db_session.query(models.Job).filter(
        models.Job.job_id == job_id,
        models.Job.user_id == user_id,
    ).first()

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job.result:
        result = json.loads(job.result)
        if "contact_id" in result:
            contact = db_session.query(models.Contact).filter(
                models.Contact.id == result["contact_id"],
                models.Contact.user_id == user_id,
            ).first()
            if contact:
                return {"success": True, "data": _contact_to_dict(contact)}

    return {"success": False, "message": "Contact not yet created from this recording"}


@router.post("/quick-capture")
def quick_capture_contact(
    request: QuickCaptureRequest,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Quick text-based contact capture (skip audio recording)."""
    try:
        # Dispatch to contact creation task
        create_contact_from_transcript.delay(
            user_id=user_id,
            job_id=f"quick-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
            transcript=f"{request.name}: {request.note}",
            event_name=request.event_name,
            mode="recap",
        )

        return {
            "success": True,
            "message": "Contact capture started. Processing in background.",
        }
    except Exception as e:
        logger.error(f"[user_id={user_id}] Quick capture failed: {e}")
        # Fallback: create contact directly
        contact = models.Contact(
            user_id=user_id,
            name=request.name,
            notes=request.note,
            event_name=request.event_name,
            last_interaction_at=datetime.utcnow(),
        )
        db_session.add(contact)
        db_session.commit()
        db_session.refresh(contact)
        return {"success": True, "data": _contact_to_dict(contact)}


@router.get("/")
def list_contacts(
    event: Optional[str] = None,
    starred: Optional[bool] = None,
    tag: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = "recent",
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=100),
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """List contacts with filters and pagination."""
    query = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id
    )

    # Apply filters
    if event:
        query = query.filter(models.Contact.event_name == event)
    if starred:
        query = query.filter(models.Contact.is_starred == True)
    if tag:
        query = query.filter(models.Contact.tags.contains([tag]))
    if date_from:
        query = query.filter(models.Contact.created_at >= date_from)
    if date_to:
        query = query.filter(models.Contact.created_at <= date_to)

    # Apply sort
    if sort == "strength":
        query = query.order_by(desc(models.Contact.relationship_strength))
    elif sort == "name":
        query = query.order_by(asc(models.Contact.name))
    elif sort == "overlap":
        query = query.order_by(desc(models.Contact.overlap_score))
    else:  # "recent"
        query = query.order_by(desc(models.Contact.created_at))

    total = query.count()
    contacts = query.offset((page - 1) * limit).limit(limit).all()

    return {
        "success": True,
        "data": [_contact_to_dict(c) for c in contacts],
        "total": total,
        "page": page,
        "limit": limit,
    }


@router.get("/search")
def search_contacts(
    q: str = Query(..., min_length=1),
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Search contacts using full-text search."""
    query = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id,
        or_(
            models.Contact.name.ilike(f"%{q}%"),
            models.Contact.company.ilike(f"%{q}%"),
            models.Contact.role.ilike(f"%{q}%"),
            models.Contact.notes.ilike(f"%{q}%"),
            models.Contact.summary.ilike(f"%{q}%"),
        ),
    ).order_by(desc(models.Contact.created_at)).limit(20)

    contacts = query.all()
    return {
        "success": True,
        "data": [_contact_to_dict(c) for c in contacts],
        "count": len(contacts),
    }


@router.get("/upcoming-follow-ups")
def get_upcoming_follow_ups(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Get contacts with follow-ups due in the next 7 days."""
    due_by = datetime.utcnow() + timedelta(days=7)
    contacts = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id,
        models.Contact.follow_up_completed == False,
        models.Contact.follow_up_due != None,
        models.Contact.follow_up_due <= due_by,
    ).order_by(asc(models.Contact.follow_up_due)).all()

    return {
        "success": True,
        "data": [_contact_to_dict(c) for c in contacts],
        "count": len(contacts),
    }


@router.get("/events")
def get_event_names(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """List unique event names for filter dropdown."""
    events = db_session.query(models.Contact.event_name).filter(
        models.Contact.user_id == user_id,
        models.Contact.event_name != None,
    ).distinct().all()

    return {
        "success": True,
        "data": [e[0] for e in events if e[0]],
    }


@router.get("/export")
def export_contacts(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Export all contacts as JSON."""
    contacts = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id
    ).order_by(desc(models.Contact.created_at)).all()

    return {
        "success": True,
        "data": [_contact_to_dict(c) for c in contacts],
        "count": len(contacts),
        "exported_at": datetime.utcnow().isoformat(),
    }


@router.get("/{contact_id}")
def get_contact(
    contact_id: int,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Get a single contact with interaction timeline."""
    contact = db_session.query(models.Contact).filter(
        models.Contact.id == contact_id,
        models.Contact.user_id == user_id,
    ).first()

    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")

    # Get interactions
    interactions = db_session.query(models.ContactInteraction).filter(
        models.ContactInteraction.contact_id == contact_id,
        models.ContactInteraction.user_id == user_id,
    ).order_by(desc(models.ContactInteraction.recorded_at)).all()

    contact_data = _contact_to_dict(contact)
    contact_data["interactions"] = [
        {
            "id": i.id,
            "contact_id": i.contact_id,
            "interaction_type": i.interaction_type,
            "content": i.content,
            "recorded_at": i.recorded_at.isoformat() if i.recorded_at else None,
        }
        for i in interactions
    ]

    return {"success": True, "data": contact_data}


@router.patch("/{contact_id}")
def update_contact(
    contact_id: int,
    request: ContactUpdate,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Update a contact's fields."""
    contact = db_session.query(models.Contact).filter(
        models.Contact.id == contact_id,
        models.Contact.user_id == user_id,
    ).first()

    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")

    update_data = request.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(contact, field, value)

    try:
        db_session.commit()
        db_session.refresh(contact)
        return {"success": True, "data": _contact_to_dict(contact)}
    except Exception as e:
        db_session.rollback()
        raise HTTPException(status_code=500, detail="Failed to update contact")


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_contact(
    contact_id: int,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Delete a contact."""
    contact = db_session.query(models.Contact).filter(
        models.Contact.id == contact_id,
        models.Contact.user_id == user_id,
    ).first()

    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")

    db_session.delete(contact)
    db_session.commit()


@router.post("/{contact_id}/star")
def toggle_starred(
    contact_id: int,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Toggle starred status."""
    contact = db_session.query(models.Contact).filter(
        models.Contact.id == contact_id,
        models.Contact.user_id == user_id,
    ).first()

    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")

    contact.is_starred = not contact.is_starred
    db_session.commit()
    db_session.refresh(contact)

    return {"success": True, "data": _contact_to_dict(contact)}


@router.post("/{contact_id}/follow-up-complete")
def mark_follow_up_complete(
    contact_id: int,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Mark follow-up as completed."""
    contact = db_session.query(models.Contact).filter(
        models.Contact.id == contact_id,
        models.Contact.user_id == user_id,
    ).first()

    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")

    contact.follow_up_completed = True
    contact.follow_up_sent = True

    # Create follow-up interaction
    interaction = models.ContactInteraction(
        user_id=user_id,
        contact_id=contact_id,
        interaction_type="follow_up_completed",
        content="Follow-up marked as completed",
    )
    db_session.add(interaction)

    contact.interaction_count = (contact.interaction_count or 1) + 1
    contact.last_interaction_at = datetime.utcnow()

    db_session.commit()
    db_session.refresh(contact)

    return {"success": True, "data": _contact_to_dict(contact)}
