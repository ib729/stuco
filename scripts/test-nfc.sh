#!/bin/bash
# Quick test script for NFC broadcaster

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

cd "$PROJECT_ROOT"
source .venv/bin/activate

# Use placeholder values for local testing (can be overridden via env vars)
export NFC_TAP_SECRET="${NFC_TAP_SECRET:-test-secret}"
export PN532_DEVICE="${PN532_DEVICE:-tty:USB0:pn532}"
export NEXTJS_URL="${NEXTJS_URL:-http://localhost:3000}"
export POS_LANE_ID="${POS_LANE_ID:-default}"

echo "Testing NFC broadcaster..."
python tap-broadcaster.py --test

