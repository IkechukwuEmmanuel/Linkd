"""Contact creation tasks using Celery.

Creates contact records from processed transcripts by:
1. Using Gemini to extract contact info (name, company, interests)
2. Computing overlap with user personas
3. Generating follow-up draft
4. Creating Contact + ContactInteraction records
"""

import json
import logging
from datetime import datetime, timedelta
from celery import Task
from ..celery_app import app
from ..db import SessionLocal
from ..models import Contact, ContactInteraction, Job, UserPersona
from ..config import settings

logger = logging.getLogger(__name__)


class ContactTask(Task):
    """Base task for contact creation."""
    autoretry_for = (Exception,)
    retry_kwargs = {"max_retries": 3}
    retry_backoff = True


@app.task(bind=True, base=ContactTask, name="src.tasks.contact_tasks.create_contact_from_transcript")
def create_contact_from_transcript(
    self,
    user_id: int,
    job_id: str,
    transcript: str,
    event_name: str = None,
    event_date: str = None,
    mode: str = "recap",
):
    """Create a Contact record from a processed transcript.

    Pipeline:
    1. Extract contact info via Gemini
    2. Compute overlap with user personas
    3. Generate follow-up draft
    4. Create DB records
    """
    logger.info(f"[job_id={job_id}] Creating contact from transcript")
    self.update_state(state="CONTACT_CREATION", meta={"progress": "Extracting contact info..."})

    db = SessionLocal()
    try:
        # Step 1: Extract contact info with Gemini
        contact_info = _extract_contact_info(transcript)

        # Step 2: Get user personas for overlap
        personas = db.query(UserPersona).filter(
            UserPersona.user_id == user_id
        ).all()
        persona_labels = [p.label for p in personas]

        # Step 3: Compute overlap
        overlap_result = _compute_overlap(contact_info, persona_labels)

        # Step 4: Generate follow-up draft
        follow_up = _generate_follow_up(contact_info, overlap_result)

        # Step 5: Calculate follow-up due date
        overlap_score = overlap_result.get("overlap_score", 0.0)
        days_ahead = 2 if overlap_score > 0.7 else 3
        follow_up_due = datetime.utcnow() + timedelta(days=days_ahead)

        # Step 6: Create Contact record
        contact = Contact(
            user_id=user_id,
            name=contact_info.get("name", "Unknown Contact"),
            company=contact_info.get("company"),
            role=contact_info.get("role"),
            email=contact_info.get("email"),
            phone=contact_info.get("phone"),
            linkedin_url=contact_info.get("linkedin"),
            event_name=event_name,
            event_date=event_date,
            interests=contact_info.get("interests", []),
            opportunities=contact_info.get("opportunities", []),
            summary=contact_info.get("summary"),
            overlap_points=overlap_result.get("overlap_points", []),
            overlap_score=overlap_score,
            follow_up_draft=follow_up,
            follow_up_due=follow_up_due,
            relationship_strength=max(1, min(10, int(overlap_score * 10))),
            last_interaction_at=datetime.utcnow(),
            source_type="voice_note",
            source_recording_id=job_id,
        )
        db.add(contact)
        db.flush()

        # Step 7: Create initial ContactInteraction
        interaction = ContactInteraction(
            user_id=user_id,
            contact_id=contact.id,
            interaction_type="initial_capture",
            content=transcript[:2000],
        )
        db.add(interaction)

        # Step 8: Update job result with contact_id
        job = db.query(Job).filter(Job.job_id == job_id).first()
        if job:
            job.status = "completed"
            job.result = json.dumps({
                "contact_id": contact.id,
                "contact_name": contact.name,
                "overlap_score": overlap_score,
            })
            job.completed_at = datetime.utcnow()

        db.commit()

        logger.info(
            f"[job_id={job_id}] Contact created: id={contact.id}, "
            f"name={contact.name}, overlap={overlap_score:.2f}"
        )

        return {
            "contact_id": contact.id,
            "contact_name": contact.name,
            "overlap_score": overlap_score,
            "follow_up_due": follow_up_due.isoformat(),
        }

    except Exception as e:
        db.rollback()
        logger.error(f"[job_id={job_id}] Contact creation failed: {e}")
        raise
    finally:
        db.close()


def _extract_contact_info(transcript: str) -> dict:
    """Use Gemini to extract contact information from transcript."""
    try:
        import google.genai as genai
        client = genai.Client(api_key=settings.gemini_api_key)

        prompt = f"""Extract contact information from this voice note transcript.

Transcript: {transcript[:2000]}

Return a JSON object with:
- "name": Person's full name (required)
- "company": Their company/organization
- "role": Their job title/role
- "email": Email if mentioned
- "phone": Phone if mentioned
- "linkedin": LinkedIn URL if mentioned
- "interests": Array of 3-5 key interests/topics they care about
- "opportunities": Array of 1-3 potential collaboration/business opportunities
- "summary": 2-sentence summary of who they are and what they do

Return ONLY valid JSON."""

        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=0.5,
                max_output_tokens=600,
            ),
        )

        output = response.text.strip()
        if output.startswith("```"):
            output = output.split("\n", 1)[-1]
            if output.endswith("```"):
                output = output[:-3]
            output = output.strip()

        return json.loads(output)
    except Exception as e:
        logger.error(f"Contact info extraction failed: {e}")
        return {"name": "Unknown Contact", "interests": [], "opportunities": []}


def _compute_overlap(contact_info: dict, persona_labels: list) -> dict:
    """Compute overlap between contact interests and user personas."""
    contact_interests = contact_info.get("interests", [])
    if not contact_interests or not persona_labels:
        return {"overlap_points": [], "overlap_score": 0.0}

    try:
        import google.genai as genai
        client = genai.Client(api_key=settings.gemini_api_key)

        prompt = f"""Compare these two lists and find shared interests/overlaps.

User's Interests: {', '.join(persona_labels[:10])}
Contact's Interests: {', '.join(contact_interests[:10])}

Return JSON:
- "overlap_points": Array of 2-4 specific shared interests or complementary areas
- "overlap_score": Float 0.0-1.0 representing how well they align (0=no overlap, 1=perfect match)

Return ONLY valid JSON."""

        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=0.3,
                max_output_tokens=300,
            ),
        )

        output = response.text.strip()
        if output.startswith("```"):
            output = output.split("\n", 1)[-1]
            if output.endswith("```"):
                output = output[:-3]
            output = output.strip()

        return json.loads(output)
    except Exception as e:
        logger.error(f"Overlap computation failed: {e}")
        return {"overlap_points": [], "overlap_score": 0.3}


def _generate_follow_up(contact_info: dict, overlap_result: dict) -> str:
    """Generate a follow-up message draft."""
    try:
        import google.genai as genai
        client = genai.Client(api_key=settings.gemini_api_key)

        name = contact_info.get("name", "there")
        overlap_points = overlap_result.get("overlap_points", [])

        prompt = f"""Write a brief, genuine follow-up message to send to {name}.

Shared interests: {', '.join(overlap_points) if overlap_points else 'general professional connection'}
Their role: {contact_info.get('role', 'unknown')} at {contact_info.get('company', 'unknown')}

Guidelines:
- 2-3 sentences max
- Reference a specific shared interest
- Suggest a concrete next step
- Sound natural, not salesy

Return ONLY the message text."""

        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=0.7,
                max_output_tokens=200,
            ),
        )

        return response.text.strip()
    except Exception as e:
        logger.error(f"Follow-up generation failed: {e}")
        return f"Hi {contact_info.get('name', 'there')}, great connecting with you! Would love to continue our conversation."
