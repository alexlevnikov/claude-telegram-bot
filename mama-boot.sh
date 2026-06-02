#!/usr/bin/env bash
# Идемпотентный бутстрап бота «Вовка» (для мамы).
# ВАЖНО: запускать из ЖИВОГО терминала (его открывает mama-boot.command через
# `open -a Terminal`), т.к. screen/TUI нужен настоящий tty. Напрямую под launchd
# НЕ работает (нет tty). Логика:
#   - если screen-сессия claude-mama жива → ничего не делает;
#   - если мертва → поднимает заново.
# Отдельный инстанс, не пересекается с основным билд-сервером.

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color

SESSION="${TMUX_SESSION:-claude-mama}"
BUILD_DIR="${BUILD_DIR:-$HOME/Documents/MamaBot}"
[ -d "$BUILD_DIR" ] || BUILD_DIR="$HOME"
TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram-mama}"
BS="$HOME/.claude/buildserver"

if ! command -v screen >/dev/null 2>&1; then
  echo "$(date '+%F %T') screen не установлен — пропускаю" >&2
  exit 0
fi

# Убираем «мёртвые» сессии, чтобы их сокеты не маскировали реальное состояние.
screen -wipe >/dev/null 2>&1

# Уже работает — только если сессия ЖИВАЯ (Detached/Attached), а не мёртвый сокет.
# [[:space:]] после имени отсекает совпадение с "${SESSION}-test" и т.п.
if screen -ls 2>/dev/null | grep -E "\.${SESSION}[[:space:]].*(Detached|Attached)" >/dev/null; then
  exit 0
fi

echo "$(date '+%F %T') поднимаю бота «Вовка» в screen '$SESSION' (cwd=$BUILD_DIR)" >&2

screen -L -Logfile "$BS/mama.screen.log" -dmS "$SESSION" bash -c "
  export TMUX_SESSION='$SESSION'
  export BUILD_DIR='$BUILD_DIR'
  export TELEGRAM_STATE_DIR='$TELEGRAM_STATE_DIR'
  export PATH='$HOME/.local/bin:$HOME/.bun/bin:$PATH'
  exec '$BS/mama-server.sh' 'Mama Bot'
"
