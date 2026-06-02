#!/usr/bin/env bash
# Личный бот «Вовка» (для мамы). Отдельный, изолированный инстанс Claude Code:
#   - свой Telegram-бот (токен в ~/.claude/channels/telegram-mama/.env)
#   - своя рабочая папка ~/Documents/MamaBot (своя память, своя персона CLAUDE.md)
#   - НЕ выставляет BUILD_SERVER=1 → хуки билд-сервера его не трогают
#   - НЕ Remote Control (один слот на машину держит основной билд-сервер)
#
# ВАЖНО про запуск: claude — интерактивный TUI, ему нужен НАСТОЯЩИЙ псевдотерминал.
# launchd его дать не может (TUI не инициализируется, канал не поднимается).
# Поэтому запускаем этот скрипт ВНУТРИ screen, который стартует из живого
# терминала (см. mama-boot.sh) — ровно как основной билд-сервер.
#
# Доступ к боту управляется ТОЛЬКО через access.json (allowlist) в state-каталоге.

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color

# Изоляция: отдельный каталог состояния Telegram и отдельная рабочая папка.
export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram-mama}"
export BUILD_DIR="${BUILD_DIR:-$HOME/Documents/MamaBot}"

cd "$BUILD_DIR" || { echo "не могу перейти в $BUILD_DIR" >&2; exit 1; }

# caffeinate не даёт Mac уснуть, пока бот работает. pty даёт screen.
exec caffeinate -dimsu claude --channels "plugin:telegram@claude-plugins-official"
