"""Task module initialization.

Imports all task definitions to register them with Celery.
"""

# Import all task modules to register with Celery
from . import transcription_tasks
from . import enrichment_tasks
from . import synthesis_tasks
from . import contact_tasks
from . import reminder_tasks

__all__ = [
    "transcription_tasks",
    "enrichment_tasks",
    "synthesis_tasks",
    "contact_tasks",
    "reminder_tasks",
]
