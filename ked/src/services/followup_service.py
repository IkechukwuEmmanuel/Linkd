"""Follow-up scheduling and suggestions service.

Calculates follow-up dates, suggests channels, and manages due follow-ups.
"""

import logging
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import asc

from ..models import Contact

logger = logging.getLogger(__name__)


def calculate_follow_up_date(
    event_type: str = "general",
    relationship_strength: int = 5,
    overlap_score: float = 0.5,
) -> datetime:
    """Calculate optimal follow-up date based on relationship signals.

    Args:
        event_type: Type of event (conference, meetup, casual, general)
        relationship_strength: 1-10 scale
        overlap_score: 0.0-1.0 overlap with user personas

    Returns:
        Recommended follow-up datetime
    """
    # Base days by event type
    base_days = {
        "conference": 2,
        "meetup": 3,
        "casual": 5,
        "general": 3,
    }.get(event_type, 3)

    # Adjust for relationship strength (higher = sooner)
    if relationship_strength >= 8:
        base_days -= 1
    elif relationship_strength <= 3:
        base_days += 2

    # Adjust for overlap score (higher = sooner)
    if overlap_score > 0.7:
        base_days -= 1
    elif overlap_score < 0.3:
        base_days += 1

    # Minimum 1 day, maximum 7 days
    days = max(1, min(7, base_days))

    return datetime.utcnow() + timedelta(days=days)


def get_due_follow_ups(user_id: int, days_ahead: int = 7, db_session: Session = None) -> list:
    """Get contacts with follow-ups due within N days."""
    if not db_session:
        return []

    due_by = datetime.utcnow() + timedelta(days=days_ahead)

    contacts = db_session.query(Contact).filter(
        Contact.user_id == user_id,
        Contact.follow_up_completed == False,
        Contact.follow_up_due != None,
        Contact.follow_up_due <= due_by,
    ).order_by(asc(Contact.follow_up_due)).all()

    return contacts


def suggest_follow_up_channel(contact: Contact) -> str:
    """Suggest the best follow-up channel for a contact.

    Args:
        contact: Contact record

    Returns:
        Suggested channel: 'linkedin', 'email', or 'whatsapp'
    """
    if contact.linkedin_url:
        return "linkedin"
    elif contact.email:
        return "email"
    elif contact.phone:
        return "whatsapp"
    else:
        return "linkedin"  # Default
