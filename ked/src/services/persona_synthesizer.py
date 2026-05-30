import json
import logging
import google.genai as genai
from ..config import settings

logger = logging.getLogger(__name__)

# Initialize new GenAI client
genai_client = genai.Client(api_key=settings.gemini_api_key)


def synthesize_persona(text: str) -> list[dict]:
    """Generate persona nodes from input text using Google Gemini.

    Returns a list of dicts with 'label' and 'weight'.
    """
    prompt = (
        "Extract and list 5-10 key professional interests or personas from the following text. "
        "Return a JSON array of objects with only \"label\" (string) and \"weight\" (integer 1-10).\n"
        f"Text: {text}\n\n"
        "Return ONLY valid JSON, no markdown or extra text."
    )
    
    try:
        response = genai_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=0.7,
                max_output_tokens=500,
            ),
        )
        output_text = response.text.strip()
        
        # Strip markdown code fences if present
        if output_text.startswith("```"):
            output_text = output_text.split("\n", 1)[-1]
            if output_text.endswith("```"):
                output_text = output_text[:-3]
            output_text = output_text.strip()
        
        nodes = json.loads(output_text)
        return nodes
    except Exception as e:
        logger.error(f"Error synthesizing personas: {e}")
        return []
