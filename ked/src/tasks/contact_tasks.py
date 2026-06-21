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
from sqlalchemy import func
from ..celery_app import app
from ..db import SessionLocal
from ..models import Contact, ContactInteraction, Job, UserPersona
from ..config import settings

logger = logging.getLogger(__name__)


def _mark_job_failed(job_id: str, reason: str):
    """Surface a terminal failure to the client: mark the local Job and the
    Supabase recording row as failed so polling endpoints stop reporting
    'processing' forever."""
    if not job_id:
        return
    try:
        s = SessionLocal()
        try:
            job = s.query(Job).filter(Job.job_id == job_id).first()
            if job:
                job.status = "failed"
                job.error_message = reason[:1000]
                job.completed_at = datetime.utcnow()
                s.commit()
        finally:
            s.close()
    except Exception as e:
        logger.warning(f"[job_id={job_id}] Could not mark local job failed: {e}")
    try:
        from ..supabase_client import SupabaseManager
        SupabaseManager.get_client().table("recordings").update(
            {"status": "failed"}
        ).eq("job_id", job_id).execute()
    except Exception as e:
        logger.warning(f"[job_id={job_id}] Could not mark recording failed: {e}")


class ContactTask(Task):
    """Base task for contact creation."""
    autoretry_for = (Exception,)
    retry_kwargs = {"max_retries": 3}
    retry_backoff = True

    def on_failure(self, exc, task_id, args, kwargs, einfo):
        """Called after retries are exhausted — record a clear failure state."""
        job_id = kwargs.get("job_id") if kwargs else None
        if not job_id and args and len(args) > 1:
            job_id = args[1]
        _mark_job_failed(job_id, f"contact creation failed: {exc}")


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

    # Bind RLS context for this task (no-op when the worker uses a privileged role).
    try:
        from .. import db as _db
        _db.set_current_user_id(user_id)
    except Exception:
        pass

    db = SessionLocal()
    try:
        # Step 1: Extract contact info with Gemini
        contact_info = _extract_contact_info(transcript)

        # Step 1b: Deduplicate — if a contact with the same name already exists
        # for this user, append an interaction and merge new info instead of
        # creating a duplicate card.
        candidate_name = (contact_info.get("name") or "").strip()
        if candidate_name and candidate_name.lower() != "unknown contact":
            existing = db.query(Contact).filter(
                Contact.user_id == user_id,
                func.lower(Contact.name) == candidate_name.lower(),
            ).first()
            if existing:
                db.add(ContactInteraction(
                    user_id=user_id,
                    contact_id=existing.id,
                    interaction_type="re_capture",
                    content=transcript[:2000],
                ))
                existing.interaction_count = (existing.interaction_count or 1) + 1
                existing.last_interaction_at = datetime.utcnow()
                if contact_info.get("company") and not existing.company:
                    existing.company = contact_info["company"]
                if contact_info.get("role") and not existing.role:
                    existing.role = contact_info["role"]
                if event_name and not existing.event_name:
                    existing.event_name = event_name
                merged_interests = list(
                    set((existing.interests or []) + contact_info.get("interests", []))
                )
                existing.interests = merged_interests

                job = db.query(Job).filter(Job.job_id == job_id).first()
                if job:
                    job.status = "completed"
                    job.result = json.dumps(
                        {"contact_id": existing.id, "merged": True}
                    )
                    job.completed_at = datetime.utcnow()
                db.commit()

                # Surface the merge on the Supabase recording too.
                try:
                    from ..supabase_client import SupabaseManager
                    SupabaseManager.get_client().table("recordings").update(
                        {"contact_id": existing.id, "status": "completed"}
                    ).eq("job_id", job_id).execute()
                except Exception as e:
                    logger.warning(
                        f"[job_id={job_id}] Supabase contact_id update (merge) failed: {e}"
                    )

                logger.info(
                    f"[job_id={job_id}] Merged into existing contact id={existing.id}"
                )
                return {"contact_id": existing.id, "merged": True}

        # Step 2: Get user personas for overlap
        personas = db.query(UserPersona).filter(
            UserPersona.user_id == user_id
        ).all()
        persona_labels = [p.label for p in personas]

        # Step 3: Compute overlap (pgvector ranks against the PEP, Gemini explains)
        overlap_result = _compute_overlap(user_id, contact_info, persona_labels)

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
        contact_id = contact.id

        # Write the contact_id back onto the Supabase recordings row so the
        # /ingest/status/{job_id} endpoint can report completion to the client.
        # Quick-capture jobs (job_id="quick-...") have no recordings row, so the
        # update simply matches zero rows — that is expected and harmless.
        try:
            from ..supabase_client import SupabaseManager
            sb_client = SupabaseManager.get_client()
            sb_client.table("recordings").update(
                {"contact_id": contact_id, "status": "completed"}
            ).eq("job_id", job_id).execute()
        except Exception as e:
            logger.warning(
                f"[job_id={job_id}] Failed to update Supabase recording with contact_id: {e}"
            )

        logger.info(
            f"[job_id={job_id}] Contact created: id={contact_id}, "
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


def _compute_overlap(user_id: int, contact_info: dict, persona_labels: list) -> dict:
    """Compute overlap between a contact and the user's Personal Enrichment Profile.

    Hybrid strategy:
      1. pgvector RANKS — embed the contact's interests and compare against the
         user's persona vectors (``compute_persona_matches``) to get the matched
         personas and a real cosine-similarity score.
      2. Gemini EXPLAINS — turn the top matches into 2-4 human "overlap points".

    Falls back to a pure-LLM overlap if embeddings/pgvector are unavailable (e.g.
    personas were created without vectors), so a card is always produced.
    """
    contact_interests = contact_info.get("interests", [])
    if not contact_interests:
        return {"overlap_points": [], "overlap_score": 0.0, "matched_personas": []}

    # --- 1. Vector ranking against the PEP ---------------------------------
    try:
        from ..services.gemini_integration import embed_text
        from ..services.overlap import compute_persona_matches

        vector = embed_text(", ".join(contact_interests[:15]))
        # threshold=0 so we always learn the best available match; the score we
        # return is the real similarity, so weak matches read as weak.
        matches = compute_persona_matches(user_id, vector, threshold=0.0, top_k=5)
    except Exception as e:
        logger.warning(f"Vector overlap unavailable, falling back to LLM: {e}")
        matches = []

    if matches:
        top = matches[0]
        score = max(0.0, min(1.0, round(float(top["similarity"]), 3)))
        matched_labels = [m["label"] for m in matches[:3]]
        overlap_points = _explain_overlap(contact_interests, matched_labels)
        if not overlap_points:
            overlap_points = matched_labels
        return {
            "overlap_points": overlap_points,
            "overlap_score": score,
            "matched_personas": [
                {"id": m.get("persona_id"), "label": m["label"],
                 "similarity": round(float(m["similarity"]), 3)}
                for m in matches
            ],
        }

    # --- 2. Fallback: pure-LLM overlap ------------------------------------
    return _llm_overlap(contact_info, persona_labels)


def _explain_overlap(contact_interests: list, persona_labels: list) -> list:
    """Use Gemini to describe the shared ground for the top-ranked personas."""
    if not persona_labels:
        return []
    try:
        import google.genai as genai
        client = genai.Client(api_key=settings.gemini_api_key)

        prompt = f"""These are the user's most relevant identity facets and a new
contact's interests. In 2-4 short phrases, name the concrete shared ground or
complementary areas between them.

User's matched facets: {', '.join(persona_labels)}
Contact's interests: {', '.join(contact_interests[:10])}

Return ONLY a JSON array of strings."""

        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=0.3, max_output_tokens=200
            ),
        )
        output = response.text.strip()
        if output.startswith("```"):
            output = output.split("\n", 1)[-1]
            if output.endswith("```"):
                output = output[:-3]
            output = output.strip()
        points = json.loads(output)
        return points if isinstance(points, list) else []
    except Exception as e:
        logger.warning(f"Overlap explanation failed: {e}")
        return []


def _llm_overlap(contact_info: dict, persona_labels: list) -> dict:
    """Pure-LLM overlap (fallback when the user has no persona vectors yet)."""
    contact_interests = contact_info.get("interests", [])
    if not contact_interests or not persona_labels:
        return {"overlap_points": [], "overlap_score": 0.0, "matched_personas": []}

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
                temperature=0.3, max_output_tokens=300
            ),
        )
        output = response.text.strip()
        if output.startswith("```"):
            output = output.split("\n", 1)[-1]
            if output.endswith("```"):
                output = output[:-3]
            output = output.strip()
        result = json.loads(output)
        result.setdefault("matched_personas", [])
        return result
    except Exception as e:
        logger.error(f"Overlap computation failed: {e}")
        return {"overlap_points": [], "overlap_score": 0.3, "matched_personas": []}


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
