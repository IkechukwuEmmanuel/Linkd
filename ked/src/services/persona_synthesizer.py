import json
import google.genai as genai
from ..config import settings

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
            model="gemini-2.0-flash-exp",
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                temperature=0.7,
                max_output_tokens=500,
            ),
        )
        nodes = json.loads(response.text.strip())
        return nodes
    except Exception as e:
        print(f"Error synthesizing personas: {e}")
        return []
