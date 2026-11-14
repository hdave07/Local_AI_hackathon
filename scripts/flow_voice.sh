#!/bin/zsh
# Track B voice harness: microphone (or --file) → Argmax → Bonsai → mock consumer.
# Executes nothing. Loads ARGMAX_API_KEY etc. from the git-ignored .env if present.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f .env ]]; then set -a; source ./.env; set +a; fi
swift build -q --product flow-voice
exec .build/debug/flow-voice "$@"
