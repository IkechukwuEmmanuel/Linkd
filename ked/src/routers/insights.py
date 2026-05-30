"""Network insights router — analytics about the user's contact network.

All endpoints require JWT authentication.
"""

import logging
from datetime import datetime, timedelta
from collections import Counter
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from .. import models, db
from ..auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/insights", tags=["insights"])


def get_db():
    session = db.SessionLocal()
    try:
        yield session
    finally:
        session.close()


@router.get("/summary")
def get_insights_summary(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Get network insights summary — total contacts, follow-ups, clusters, recent."""
    try:
        # Total contacts
        total_contacts = db_session.query(models.Contact).filter(
            models.Contact.user_id == user_id
        ).count()

        # Follow-ups due
        due_by = datetime.utcnow() + timedelta(days=7)
        follow_ups_due = db_session.query(models.Contact).filter(
            models.Contact.user_id == user_id,
            models.Contact.follow_up_completed == False,
            models.Contact.follow_up_due != None,
            models.Contact.follow_up_due <= due_by,
        ).count()

        # Starred contacts
        starred_contacts = db_session.query(models.Contact).filter(
            models.Contact.user_id == user_id,
            models.Contact.is_starred == True,
        ).count()

        # Interest clusters
        contacts = db_session.query(models.Contact).filter(
            models.Contact.user_id == user_id
        ).all()

        interest_counter = Counter()
        for contact in contacts:
            for interest in (contact.interests or []):
                interest_counter[interest] += 1

        clusters = [
            {"interest": interest, "contact_count": count}
            for interest, count in interest_counter.most_common(10)
        ]

        # Recent contacts
        recent = db_session.query(models.Contact).filter(
            models.Contact.user_id == user_id,
        ).order_by(desc(models.Contact.created_at)).limit(5).all()

        recent_data = []
        for c in recent:
            recent_data.append({
                "id": c.id,
                "name": c.name,
                "company": c.company,
                "overlap_score": c.overlap_score or 0.0,
                "created_at": c.created_at.isoformat() if c.created_at else None,
            })

        return {
            "success": True,
            "data": {
                "total_contacts": total_contacts,
                "follow_ups_due": follow_ups_due,
                "starred_contacts": starred_contacts,
                "clusters": clusters,
                "recent_contacts": recent_data,
            },
        }

    except Exception as e:
        logger.error(f"[user_id={user_id}] Insights summary failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to get insights")


@router.get("/clusters")
def get_interest_clusters(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Group contacts by shared interests."""
    contacts = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id
    ).all()

    interest_map = {}
    for contact in contacts:
        for interest in (contact.interests or []):
            if interest not in interest_map:
                interest_map[interest] = []
            interest_map[interest].append({
                "id": contact.id,
                "name": contact.name,
                "company": contact.company,
            })

    clusters = [
        {"cluster": interest, "contacts": contacts_list, "count": len(contacts_list)}
        for interest, contacts_list in sorted(interest_map.items(), key=lambda x: -len(x[1]))
    ]

    return {"success": True, "data": clusters[:15]}


@router.get("/velocity")
def get_relationship_velocity(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Get contacts per week and follow-up completion rate."""
    # Contacts in last 4 weeks
    four_weeks_ago = datetime.utcnow() - timedelta(weeks=4)
    recent_count = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id,
        models.Contact.created_at >= four_weeks_ago,
    ).count()

    contacts_per_week = round(recent_count / 4, 1)

    # Follow-up rate
    total_with_followup = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id,
        models.Contact.follow_up_due != None,
    ).count()

    completed_followup = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id,
        models.Contact.follow_up_completed == True,
    ).count()

    followup_rate = (completed_followup / total_with_followup * 100) if total_with_followup > 0 else 0

    return {
        "success": True,
        "data": {
            "contacts_per_week": contacts_per_week,
            "follow_up_rate": round(followup_rate, 1),
            "total_contacts_4_weeks": recent_count,
        },
    }


@router.get("/dormant")
def get_dormant_contacts(
    days: int = 30,
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Get high-overlap contacts inactive for N days."""
    cutoff = datetime.utcnow() - timedelta(days=days)

    contacts = db_session.query(models.Contact).filter(
        models.Contact.user_id == user_id,
        models.Contact.overlap_score > 0.5,
        models.Contact.last_interaction_at < cutoff,
    ).order_by(desc(models.Contact.overlap_score)).limit(10).all()

    return {
        "success": True,
        "data": [
            {
                "id": c.id,
                "name": c.name,
                "company": c.company,
                "overlap_score": c.overlap_score,
                "last_interaction_at": c.last_interaction_at.isoformat() if c.last_interaction_at else None,
                "days_inactive": (datetime.utcnow() - c.last_interaction_at).days if c.last_interaction_at else None,
            }
            for c in contacts
        ],
    }
