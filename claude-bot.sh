#!/usr/bin/env bash
# Управление Telegram-ботами Claude: главный билд-сервер + мама-бот.
# Использование:
#   claude-bot.sh start   — запустить все боты
#   claude-bot.sh stop    — остановить все боты
#   claude-bot.sh status  — показать статус
#   claude-bot.sh restart — перезапустить все боты

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color

BS="$HOME/.claude/buildserver"
MAIN_SESSION="claude"
MAMA_SESSION="claude-mama"
MAIN_DIR="${BUILD_DIR:-$HOME/Documents/Projects}"
MAMA_DIR="$HOME/Documents/MamaBot"

# ── Хелперы ────────────────────────────────────────────────────────────────

session_alive() {
  screen -ls 2>/dev/null | grep -E "\.${1}[[:space:]].*(Detached|Attached)" >/dev/null
}

print_status() {
  local name="$1" session="$2"
  if session_alive "$session"; then
    local pid
    pid=$(screen -ls 2>/dev/null | grep -E "\.${session}[[:space:]]" | awk -F'[. \t]' '{print $2}')
    echo "  ✅ $name  →  screen:$session  (PID $pid)"
  else
    echo "  ⛔ $name  →  не запущен"
  fi
}

# ── Start ───────────────────────────────────────────────────────────────────

start_main() {
  if session_alive "$MAIN_SESSION"; then
    echo "  ✅ Билд-сервер уже работает (screen:$MAIN_SESSION)"
    return
  fi
  [ -d "$MAIN_DIR" ] || { echo "  ⚠️  BUILD_DIR не найден: $MAIN_DIR"; return 1; }
  screen -dmS "$MAIN_SESSION" bash -c "
    export BUILD_SERVER=1 TMUX_SESSION='$MAIN_SESSION' BUILD_DIR='$MAIN_DIR'
    export COMPACT_THRESHOLD='${COMPACT_THRESHOLD:-35}'
    export CLEAR_THRESHOLD='${CLEAR_THRESHOLD:-80}'
    export PATH='$HOME/.local/bin:$HOME/.bun/bin:$PATH'
    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TERM=xterm-256color
    cd '$MAIN_DIR'
    exec caffeinate -dimsu claude --remote-control \"Build Server\" --channels \"plugin:telegram@claude-plugins-official\"
  "
  echo "  🚀 Билд-сервер запущен (screen:$MAIN_SESSION, cwd:$MAIN_DIR, remote-control: on)"
}

start_mama() {
  if session_alive "$MAMA_SESSION"; then
    echo "  ✅ Бот «Вовка» уже работает (screen:$MAMA_SESSION)"
    return
  fi
  if [ ! -d "$MAMA_DIR" ]; then
    echo "  ⏭️  Бот «Вовка» пропущен — папка не найдена: $MAMA_DIR"
    return
  fi
  local mama_env="$HOME/.claude/channels/telegram-mama/.env"
  if [ ! -f "$mama_env" ]; then
    echo "  ⏭️  Бот «Вовка» пропущен — нет токена: $mama_env"
    return
  fi
  screen -dmS "$MAMA_SESSION" bash -c "
    export TMUX_SESSION='$MAMA_SESSION'
    export TELEGRAM_STATE_DIR='$HOME/.claude/channels/telegram-mama'
    export COMPACT_THRESHOLD='${COMPACT_THRESHOLD:-35}'
    export CLEAR_THRESHOLD='${CLEAR_THRESHOLD:-80}'
    export PATH='$HOME/.local/bin:$HOME/.bun/bin:$PATH'
    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TERM=xterm-256color
    cd '$MAMA_DIR'
    exec caffeinate -dimsu claude --remote-control \"Mama Bot\" --channels \"plugin:telegram@claude-plugins-official\"
  "
  echo "  🚀 Бот «Вовка» запущен (screen:$MAMA_SESSION, cwd:$MAMA_DIR, remote-control: on)"
}

# ── Stop ────────────────────────────────────────────────────────────────────

stop_session() {
  local name="$1" session="$2"
  screen -wipe >/dev/null 2>&1
  if session_alive "$session"; then
    screen -S "$session" -X quit 2>/dev/null
    sleep 0.5
    if session_alive "$session"; then
      local pid
      pid=$(screen -ls 2>/dev/null | grep -E "\.${session}[[:space:]]" | awk -F'[. \t]' '{print $2}')
      [ -n "$pid" ] && kill "$pid" 2>/dev/null
    fi
    echo "  🛑 $name остановлен"
  else
    echo "  ⚪ $name уже был остановлен"
  fi
}

stop_hooks() {
  pkill -f "buildserver/on-stop.ts"       2>/dev/null
  pkill -f "buildserver/prompt-submitted" 2>/dev/null
  pkill -f "buildserver/progress.ts"      2>/dev/null
  pkill -f "buildserver/compact-check"    2>/dev/null
  rm -f /tmp/claude-tg-progress-*.json   2>/dev/null
  rm -f "$BS/state/prompt-active.json"   2>/dev/null
  rm -f "$BS/state/prompt-active.alerted" 2>/dev/null
}

# ── Commands ────────────────────────────────────────────────────────────────

cmd_start() {
  echo "▶ Запуск ботов..."
  screen -wipe >/dev/null 2>&1
  start_main
  start_mama
  echo ""
  echo "Подключиться: screen -r $MAIN_SESSION  |  screen -r $MAMA_SESSION"
}

cmd_stop() {
  echo "⏹ Остановка ботов..."
  stop_session "Билд-сервер" "$MAIN_SESSION"
  stop_session "Бот «Вовка»" "$MAMA_SESSION"
  stop_hooks
  screen -wipe >/dev/null 2>&1
  echo ""
  echo "Проверка: screen -ls"
}

cmd_status() {
  screen -wipe >/dev/null 2>&1
  echo "── Статус ботов ──────────────────────────────"
  print_status "Билд-сервер" "$MAIN_SESSION"
  print_status "Бот «Вовка»" "$MAMA_SESSION"
  echo ""
  echo "── LaunchD агент ─────────────────────────────"
  if launchctl list 2>/dev/null | grep -q "claude-buildserver"; then
    echo "  ✅ com.alexlevnikov.claude-buildserver  (загружен)"
  else
    echo "  ⛔ LaunchD агент не загружен"
  fi
  echo ""
  local stuck="$BS/state/prompt-active.json"
  if [ -f "$stuck" ]; then
    local age=$(( ( $(date +%s) - $(stat -f %m "$stuck" 2>/dev/null || echo 0) ) / 60 ))
    echo "── Stuck-детектор ────────────────────────────"
    echo "  ⚠️  Claude занят уже ${age} мин  ($stuck)"
  fi
}

# ── Entry ───────────────────────────────────────────────────────────────────

case "${1:-status}" in
  start)          cmd_start   ;;
  stop)           cmd_stop    ;;
  restart)        cmd_stop; echo ""; sleep 1; cmd_start ;;
  status)         cmd_status  ;;
  restart-main)   stop_session "Билд-сервер" "$MAIN_SESSION"; screen -wipe >/dev/null 2>&1; start_main ;;
  restart-mama)   stop_session "Бот «Вовка»"  "$MAMA_SESSION"; screen -wipe >/dev/null 2>&1; start_mama ;;
  *)
    echo "Использование: $0 {start|stop|restart|restart-main|restart-mama|status}"
    exit 1
    ;;
esac
