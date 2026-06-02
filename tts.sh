#!/usr/bin/env bash
# Генерация голосового ответа через ElevenLabs Flash TTS.
#   tts.sh "<текст>"
# Выводит путь к .ogg файлу в stdout.
# Exit codes: 0=успех, 1=ошибка API, 2=фильтр (длинный/код), 3=дневной лимит
#
# Настройки в ~/.claude/buildserver/transcribe.env:
#   ELEVENLABS_API_KEY=sk_...
#   ELEVENLABS_TTS_VOICE=JBFqnCBsd6RMkjVDRZzb   # voice_id (George — multilingual)
#   ELEVENLABS_TTS_MODEL=eleven_flash_v2_5        # Flash: 75ms, 32 языка вкл. русский
#   TTS_DAILY_LIMIT_CHARS=50000                   # лимит символов в день (~$2.50)

set -euo pipefail
export PATH="$HOME/.bun/bin:$PATH"

TEXT="${1:?usage: tts.sh '<текст>'}"
ENVF="$HOME/.claude/buildserver/transcribe.env"
if [ -f "$ENVF" ]; then set -a; . "$ENVF"; set +a; fi

: "${ELEVENLABS_API_KEY:?ELEVENLABS_API_KEY не задан в transcribe.env}"
VOICE="${ELEVENLABS_TTS_VOICE:-JBFqnCBsd6RMkjVDRZzb}"
MODEL="${ELEVENLABS_TTS_MODEL:-eleven_flash_v2_5}"
DAILY_LIMIT="${TTS_DAILY_LIMIT_CHARS:-50000}"
STATE_DIR="$HOME/.claude/buildserver/state"
USAGE_FILE="$STATE_DIR/tts-usage.json"
TODAY="$(date +%Y-%m-%d)"

# ── умные фильтры ──────────────────────────────────────────────────────────
LEN=${#TEXT}
if [ "$LEN" -gt 500 ]; then
  echo "tts: текст слишком длинный ($LEN симв > 500)" >&2; exit 2
fi
if echo "$TEXT" | grep -qF '```'; then
  echo "tts: текст содержит код" >&2; exit 2
fi

# ── дневной бюджет ─────────────────────────────────────────────────────────
USED=$(bun -e "
try {
  const d = JSON.parse(require('fs').readFileSync('$USAGE_FILE','utf8'));
  process.stdout.write(String(d['$TODAY'] ?? 0));
} catch { process.stdout.write('0'); }
" 2>/dev/null || echo 0)

if [ "$USED" -ge "$DAILY_LIMIT" ]; then
  echo "tts: дневной лимит ${DAILY_LIMIT} симв исчерпан (использовано: ${USED})" >&2
  exit 3
fi

# ── запрос к ElevenLabs ────────────────────────────────────────────────────
OUTFILE="/tmp/claude-tts-$(date +%s)-$RANDOM.ogg"

HTTP_STATUS=$(curl -fsS -w "%{http_code}" \
  -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE}" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"text\":$(printf '%s' "$TEXT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"model_id\":\"$MODEL\",\"output_format\":\"opus_48000\"}" \
  -o "$OUTFILE" 2>/dev/null)

if [ "$HTTP_STATUS" != "200" ]; then
  echo "tts: ElevenLabs HTTP $HTTP_STATUS" >&2
  rm -f "$OUTFILE"; exit 1
fi

# ── трекинг расхода ────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR"
bun -e "
import { readFileSync, writeFileSync } from 'node:fs';
const f = '$USAGE_FILE', today = '$TODAY', n = $LEN;
let d = {}; try { d = JSON.parse(readFileSync(f,'utf8')); } catch {}
d[today] = (d[today] ?? 0) + n;
// Удаляем записи старше 30 дней
const cutoff = new Date(); cutoff.setDate(cutoff.getDate()-30);
for (const k of Object.keys(d)) if (k < cutoff.toISOString().slice(0,10)) delete d[k];
writeFileSync(f, JSON.stringify(d, null, 2));
" 2>/dev/null || true

echo "$OUTFILE"
