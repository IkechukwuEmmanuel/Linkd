#!/bin/bash

# Start Celery workers + beat for the Linkd async pipeline (local/dev).
#
# Queues:
#   - transcription : CPU-bound (Deepgram STT, synthesis)        [prefork]
#   - enrichment    : I/O-bound (scraping, source dispatch)      [gevent]
#   - default       : contact creation + reminders               [prefork]
#
# IMPORTANT: the `default` queue MUST have a consumer — create_contact_from_
# transcript (which turns a transcript into a relationship card) is routed there.
# Without this worker the pipeline transcribes but never produces a card.
#
# beat schedules the periodic reminder/maintenance tasks.

set -e

REDIS_HOST=${REDIS_HOST:-localhost}
REDIS_PORT=${REDIS_PORT:-6379}
WORKER_COUNT=${WORKER_COUNT:-4}
FLOWER_PORT=${FLOWER_PORT:-5555}

mkdir -p logs

echo "Starting Linkd workers..."
echo "Redis: $REDIS_HOST:$REDIS_PORT | Worker concurrency: $WORKER_COUNT"

PIDS=()

# Transcription worker (CPU-bound, multiprocessing)
celery -A src.celery_app worker \
    --queues transcription \
    --concurrency="$WORKER_COUNT" \
    --pool=prefork \
    --loglevel=info \
    --hostname=transcription@%h \
    --logfile=logs/transcription.log &
PIDS+=($!)
echo "[1/4] transcription worker (PID ${PIDS[-1]})"

# Enrichment worker (I/O-bound, gevent — scraping + source dispatch)
celery -A src.celery_app worker \
    --queues enrichment \
    --concurrency=$((WORKER_COUNT * 4)) \
    --pool=gevent \
    --loglevel=info \
    --hostname=enrichment@%h \
    --logfile=logs/enrichment.log &
PIDS+=($!)
echo "[2/4] enrichment worker (PID ${PIDS[-1]})"

# Default worker — contact creation + reminders (prefork; uses psycopg2/DB).
celery -A src.celery_app worker \
    --queues default \
    --concurrency="$WORKER_COUNT" \
    --pool=prefork \
    --loglevel=info \
    --hostname=default@%h \
    --logfile=logs/default.log &
PIDS+=($!)
echo "[3/4] default worker (PID ${PIDS[-1]})"

# Beat scheduler — periodic reminders / relationship-strength decay.
celery -A src.celery_app beat \
    --loglevel=info \
    --logfile=logs/beat.log &
PIDS+=($!)
echo "[4/4] beat scheduler (PID ${PIDS[-1]})"

# Optional: Flower monitoring (set DISABLE_FLOWER=1 to skip)
if [ "${DISABLE_FLOWER:-0}" != "1" ]; then
    celery -A src.celery_app flower \
        --port="$FLOWER_PORT" \
        --logfile=logs/flower.log &
    PIDS+=($!)
    echo "Flower monitoring on http://localhost:$FLOWER_PORT (PID ${PIDS[-1]})"
fi

trap "kill ${PIDS[*]} 2>/dev/null || true" EXIT
wait

echo "All workers stopped."
