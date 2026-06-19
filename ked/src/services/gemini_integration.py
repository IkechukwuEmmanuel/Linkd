"""Gemini API client integration for LLM tasks.

Provides centralized Gemini API access for:
- Persona synthesis
- Name extraction
- Identity resolution scoring
- Warm outreach generation
"""

import logging
import google.genai as genai
from ..config import settings
from ..resilience import retry_call

logger = logging.getLogger(__name__)


def _build_client():
    """Build the Gemini client with a request timeout when supported."""
    try:
        return genai.Client(
            api_key=settings.gemini_api_key,
            http_options=genai.types.HttpOptions(timeout=30_000),  # ms
        )
    except Exception:  # older/newer SDK without http_options timeout
        return genai.Client(api_key=settings.gemini_api_key)


# Initialize new GenAI client
genai_client = _build_client()


def get_gemini_client():
    """Get the Gemini API client.
    
    Returns:
        Configured genai.Client instance
    """
    return genai_client


async def generate_content(prompt: str, max_tokens: int = 500, temperature: float = 0.7) -> str:
    """Generate content using Gemini API.
    
    Args:
        prompt: The prompt to send to Gemini
        max_tokens: Maximum tokens in the response
        temperature: Temperature for generation (0.0-1.0)
        
    Returns:
        Generated text response
    """
    try:
        response = retry_call(
            lambda: genai_client.models.generate_content(
                model="gemini-2.0-flash",
                contents=prompt,
                config=genai.types.GenerateContentConfig(
                    temperature=temperature,
                    max_output_tokens=max_tokens,
                ),
            ),
            label="gemini.generate_content",
        )

        return response.text

    except Exception as e:
        logger.error(f"Gemini generation failed: {e}")
        raise


def embed_text(text: str, model: str = "text-embedding-004") -> list:
    """Generate embeddings for text using Gemini.
    
    Args:
        text: Text to embed
        model: Embedding model to use
        
    Returns:
        List of embeddings (padded to 1536)
    """
    try:
        response = retry_call(
            lambda: genai_client.models.embed_content(
                model=f"models/{model}",
                content=text,
            ),
            label="gemini.embed_content",
        )
        
        embedding = response.embeddings[0].values if hasattr(response, 'embeddings') else response.embedding
        embedding = list(embedding)
        
        # Pad to 1536 dimensions for consistency
        if len(embedding) < 1536:
            embedding = embedding + [0.0] * (1536 - len(embedding))
        else:
            embedding = embedding[:1536]
        
        return embedding
    
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise
