#!/bin/bash
# Voice transcription script
# Supports Groq Whisper API (cloud) or local whisper.cpp
# Usage: ./transcribe.sh /path/to/audio.ogg [language]
set -euo pipefail

INPUT="$1"
LANG="${2:-auto}"

if [ -z "$INPUT" ]; then
    echo "Usage: $0 <audio_file> [language]"
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

# Source .env if available (for API keys)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
[ -f "$REPO_DIR/.env" ] && set -a && . "$REPO_DIR/.env" && set +a

# ─── Groq API (cloud, fast) ───
if [ -n "${GROQ_API_KEY:-}" ]; then
    MODEL="${GROQ_WHISPER_MODEL:-whisper-large-v3-turbo}"
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        https://api.groq.com/openai/v1/audio/transcriptions \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -F file=@"$INPUT" \
        -F model="$MODEL" \
        -F response_format="text" \
        2>/dev/null)

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        echo "$BODY"
        exit 0
    else
        echo "Groq API error (HTTP $HTTP_CODE): $BODY" >&2
        echo "Falling back to local whisper..." >&2
    fi
fi

# ─── Local whisper.cpp ───
WHISPER_CLI="$HOME/whisper.cpp/build/bin/whisper-cli"
MODEL="$HOME/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin"

if [ ! -f "$WHISPER_CLI" ]; then
    echo "Error: whisper.cpp not found at $WHISPER_CLI" >&2
    echo "Install: git clone https://github.com/ggerganov/whisper.cpp ~/whisper.cpp && cd ~/whisper.cpp && make" >&2
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model not found at $MODEL" >&2
    echo "Download: cd ~/whisper.cpp && bash ./models/download-ggml-model.sh large-v3-turbo" >&2
    exit 1
fi

# Convert to WAV if needed (whisper.cpp works best with WAV)
TMPWAV=$(mktemp /tmp/whisper_XXXXXX.wav)
trap "rm -f $TMPWAV" EXIT

# Use ffmpeg to convert to 16kHz mono WAV
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg not found. Install it first." >&2
    exit 1
fi

ffmpeg -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TMPWAV" -y -loglevel error

# Run whisper (output just the transcribed text, no timestamps)
"$WHISPER_CLI" -m "$MODEL" -l "$LANG" -f "$TMPWAV" --no-timestamps 2>/dev/null | grep -E '^\s+' | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/  */ /g'
