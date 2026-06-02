#!/usr/bin/env bash
# Перезапускает сессию Claude Code с задержкой — вызывается самим Claude.
#
# Флоу:
#   1. Claude вызывает скрипт, тот сразу возвращает "scheduled" (не блокирует)
#   2. Фоновый процесс (независимый от screen-сессии) шлёт 🔴 offline
#   3. Убивает сессию и запускает новую
#   4. Ждёт пока screen-сессия поднимется, шлёт 🟢 online
#
# Использование (из CLAUDE.md):
#   ~/.claude/buildserver/new-session.sh main   — перезапустить билд-сервер
#   ~/.claude/buildserver/new-session.sh mama   — перезапустить бота Вовку

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

TARGET="${1:-}"
DELAY="${NEW_SESSION_DELAY:-4}"
BS="$HOME/.claude/buildserver"
BUN="$HOME/.bun/bin/bun"

if [ "$TARGET" != "main" ] && [ "$TARGET" != "mama" ]; then
  echo "Использование: new-session.sh main|mama" >&2
  exit 1
fi

LABEL="$( [ "$TARGET" = "mama" ] && echo "Вовка" || echo "Билд-сервер" )"
SESSION="$( [ "$TARGET" = "mama" ] && echo "claude-mama" || echo "claude" )"

# ── Хелпер: уведомление через control-бот ───────────────────────────────────
notify() {
  local text="$1"
  "$BUN" -e "
    import { send, loadControlToken } from '${BS}/tglib.ts';
    const t = loadControlToken();
    if (t) await send($(printf '%s' "$text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"), { token: t });
  " 2>/dev/null || true
}

# ── Фоновый процесс: переживает смерть screen-сессии ────────────────────────
(
  sleep "$DELAY"

  # 1. Уведомление об уходе в оффлайн
  notify "🔴 ${LABEL}: перезапуск — ухожу в оффлайн на ~15 сек"

  # 2. Перезапуск сессии
  "$BS/claude-bot.sh" "restart-${TARGET}"

  # 3. Ждём пока сессия поднимется (до 60 сек)
  for i in $(seq 1 20); do
    sleep 3
    if screen -ls 2>/dev/null | grep -qE "\.${SESSION}[[:space:]].*(Detached|Attached)"; then
      sleep 10  # Даём Telegram-плагину время подключиться

      # Перерегистрируем команды — плагин при запуске сбрасывает их на дефолтные
      bash "$BS/register-bot-commands.sh" "$TARGET" 2>/dev/null || true

      notify "🟢 ${LABEL}: снова онлайн"
      exit 0
    fi
  done

  # Если так и не поднялась — тоже сообщаем
  notify "⚠️ ${LABEL}: сессия не поднялась за 60 сек — проверь вручную"

) </dev/null >/dev/null 2>&1 &

echo "scheduled:${TARGET}:delay=${DELAY}s"
