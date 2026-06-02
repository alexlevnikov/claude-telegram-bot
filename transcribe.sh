#!/usr/bin/env bash
# Транскрипция голосового/аудио в текст.
#   transcribe.sh <путь-к-аудио>
# Печатает распознанный текст в stdout.
#
# Ключ и провайдер берутся из ~/.claude/buildserver/transcribe.env:
#   TRANSCRIBE_PROVIDER=elevenlabs        # elevenlabs | openai | mistral
#   ELEVENLABS_API_KEY=...                # для elevenlabs (Scribe)
#   OPENAI_API_KEY=sk-...                 # для openai
#   MISTRAL_API_KEY=...                   # для mistral
#
# Telegram-голос приходит как .oga/.ogg (opus) — все три API принимают его напрямую.
set -euo pipefail
export PATH="$HOME/.bun/bin:$PATH"   # bun для разбора JSON-ответа

FILE="${1:?usage: transcribe.sh <audiofile>}"
[ -f "$FILE" ] || { echo "файл не найден: $FILE" >&2; exit 1; }

ENVF="$HOME/.claude/buildserver/transcribe.env"
if [ -f "$ENVF" ]; then set -a; . "$ENVF"; set +a; fi

PROVIDER="${TRANSCRIBE_PROVIDER:-openai}"

case "$PROVIDER" in
  elevenlabs)
    : "${ELEVENLABS_API_KEY:?ELEVENLABS_API_KEY не задан в transcribe.env}"
    curl -fsS https://api.elevenlabs.io/v1/speech-to-text \
      -H "xi-api-key: $ELEVENLABS_API_KEY" \
      -F model_id="${ELEVENLABS_STT_MODEL:-scribe_v2}" \
      -F file=@"$FILE" \
      | bun -e 'console.log((JSON.parse(await Bun.stdin.text()).text ?? ""))'
    ;;
  openai)
    : "${OPENAI_API_KEY:?OPENAI_API_KEY не задан в transcribe.env}"
    curl -fsS https://api.openai.com/v1/audio/transcriptions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -F file=@"$FILE" \
      -F model="${OPENAI_TRANSCRIBE_MODEL:-whisper-1}" \
      -F response_format=text
    ;;
  mistral)
    : "${MISTRAL_API_KEY:?MISTRAL_API_KEY не задан в transcribe.env}"
    curl -fsS https://api.mistral.ai/v1/audio/transcriptions \
      -H "Authorization: Bearer $MISTRAL_API_KEY" \
      -F file=@"$FILE" \
      -F model="${MISTRAL_TRANSCRIBE_MODEL:-voxtral-mini-latest}"
    ;;
  *)
    echo "неизвестный TRANSCRIBE_PROVIDER: $PROVIDER" >&2; exit 1 ;;
esac
