"""Scheduled reminder tasks — follow-up reminders, relationship decay, cleanup.

Run via Celery Beat on cron schedules.
"""

import logging
from datetime import datetime, timedelta
from ..celery_app import app
from ..db import SessionLocal
from ..models import Contact, Notification

logger = logging.getLogger(__name__)


@app.task(name="src.tasks.reminder_tasks.send_follow_up_reminders")
def send_follow_up_reminders():
    """Find contacts with follow-ups due today and create notification records."""
    db = SessionLocal()
    try:
        today = datetime.utcnow().date()
        tomorrow = today + timedelta(days=1)

        contacts = db.query(Contact).filter(
            Contact.follow_up_completed == False,
            Contact.follow_up_due != None,
            Contact.follow_up_due >= today,
            Contact.follow_up_due < tomorrow,
        ).all()

        created = 0
        for contact in contacts:
            notification = Notification(
                user_id=contact.user_id,
                type="follow_up_reminder",
                title=f"Follow up with {contact.name}",
                body=contact.follow_up_draft or f"Time to reconnect with {contact.name}!",
                contact_id=contact.id,
            )
            db.add(notification)
            created += 1

        db.commit()
        logger.info(f"Created {created} follow-up reminders")
        return {"created": created}

    except Exception as e:
        db.rollback()
        logger.error(f"Follow-up reminders failed: {e}")
        raise
    finally:
        db.close()


@app.task(name="src.tasks.reminder_tasks.update_relationship_strength")
def update_relationship_strength():
    """Weekly: decay relationship strength for inactive contacts."""
    db = SessionLocal()
    try:
        thirty_days_ago = datetime.utcnow() - timedelta(days=30)

        contacts = db.query(Contact).filter(
            Contact.last_interaction_at < thirty_days_ago,
            Contact.relationship_strength > 1,
        ).all()

        decayed = 0
        for contact in contacts:
            contact.relationship_strength = max(1, contact.relationship_strength - 1)
            decayed += 1

        db.commit()
        logger.info(f"Decayed relationship strength for {decayed} contacts")
        return {"decayed": decayed}

    except Exception as e:
        db.rollback()
        logger.error(f"Relationship decay failed: {e}")
        raise
    finally:
        db.close()


@app.task(name="src.tasks.reminder_tasks.delete_expired_audio")
def delete_expired_audio():
    """Delete Supabase audio files older than 24 hours."""
    logger.info("Audio cleanup task ran (no-op without Supabase storage configured)")
    return {"deleted": 0}
