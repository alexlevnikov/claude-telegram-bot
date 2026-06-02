#!/usr/bin/env bash
# Идемпотентный бутстрап билд-сервера для launchd.
# Запускается при логине (RunAtLoad) и каждую минуту (StartInterval=60):
#   - если screen-сессия жива → только проверяет stuck-состояние;
#   - если мертва → поднимает заново (авто-recovery).
#   - контрол-бот (commands.ts) — всегда следит и перезапускает независимо от Claude.
# Уведомляет в Telegram при рестарте и при зависании.

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color

SESSION="${TMUX_SESSION:-claude}"
BUILD_DIR="${BUILD_DIR:-$HOME/Documents/Projects}"
[ -d "$BUILD_DIR" ] || BUILD_DIR="$HOME"
STUCK_MINUTES="${STUCK_MINUTES:-15}"
STATE_FILE="$HOME/.claude/buildserver/state/prompt-active.json"
BS="$HOME/.claude/buildserver"

# ---- Stuck-детектор -------------------------------------------------------
# Если файл prompt-active.json существует и старше STUCK_MINUTES — Claude завис.
check_stuck() {
  [ -f "$STATE_FILE" ] || return 0
  local mtime now age_min
  # macOS stat: -f %m = modification time as Unix timestamp (нет python3)
  mtime=$(stat -f %m "$STATE_FILE" 2>/dev/null) || return 0
  now=$(date +%s)
  age_min=$(( (now - mtime) / 60 ))
  [ "$age_min" -ge "$STUCK_MINUTES" ] || return 0

  # Отправляем алерт один раз — флаг .alerted убирается в notify-stop.ts (Stop hook)
  local alert_flag="${STATE_FILE%.json}.alerted"
  [ -f "$alert_flag" ] && return 0
  touch "$alert_flag"

  # Читаем cwd из JSON через awk (без python3)
  local proj cwd_val
  cwd_val=$(awk -F'"' '/"cwd"/{print $4; exit}' "$STATE_FILE" 2>/dev/null || echo "?")
  proj=$(basename "$cwd_val")

  bun "$BS/notify-stuck.ts" "$age_min" "$proj" 2>/dev/null || true
}

check_stuck

# ---- Контрол-бот (commands.ts) --------------------------------------------
# Работает независимо от Claude Code — не нужны кредиты, не зависит от screen.
# Проверяем каждую минуту: если упал — тихо поднимаем.
ensure_commands_bot() {
  local pid_file="$BS/commands.pid"
  local log_file="$BS/commands.log"

  # Живой процесс — всё ок
  if [ -f "$pid_file" ]; then
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi

  # Запасная проверка через pgrep (на случай если pid-файл устарел)
  if pgrep -f "buildserver/commands.ts" >/dev/null 2>&1; then
    # Обновляем pid-файл
    pgrep -f "buildserver/commands.ts" | head -1 > "$pid_file"
    return 0
  fi

  # Не запущен — стартуем
  echo "$(date '+%F %T') контрол-бот не найден — поднимаю" >&2
  nohup bun "$BS/commands.ts" >> "$log_file" 2>&1 &
  echo $! > "$pid_file"
}

ensure_commands_bot

# ---- Авто-recovery --------------------------------------------------------
if ! command -v screen >/dev/null 2>&1; then
  echo "$(date '+%F %T') screen не установлен — пропускаю" >&2
  exit 0
fi

# screen -ls | grep "SESSION": ищем ".<имя>" в выводе
if screen -ls 2>/dev/null | grep -q "\.${SESSION}"; then
  exit 0   # уже работает — всё ок
fi

# Сессия мертва — поднимаем и уведомляем
echo "$(date '+%F %T') поднимаю билд-сервер в screen '$SESSION' (cwd=$BUILD_DIR)" >&2

# Уведомление в Telegram о рестарте (fire-and-forget)
bun -e "
import { send, loadControlToken } from '$BS/tglib.ts';
const t = loadControlToken();
if (t) await send('🔄 Билд-сервер перезапустился', { token: t });
" 2>/dev/null || true

# screen -dmS: detached, named session
screen -dmS "$SESSION" bash -c "
  export BUILD_SERVER=1 TMUX_SESSION='$SESSION' BUILD_DIR='$BUILD_DIR'
  export COMPACT_THRESHOLD='35' CLEAR_THRESHOLD='80'
  export PATH='$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
  export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TERM=xterm-256color
  cd '$BUILD_DIR'
  exec caffeinate -dimsu claude --remote-control \"Build Server\" --channels \"plugin:telegram@claude-plugins-official\"
"
