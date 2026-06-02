#!/usr/bin/env bash
# Устанавливает и активирует launchd-агент билд-сервера.
# Запускать ПОСЛЕ: /login в Claude Code
set -euo pipefail
PLIST="$HOME/.claude/buildserver/com.alexlevnikov.claude-buildserver.plist"
DEST="$HOME/Library/LaunchAgents/com.alexlevnikov.claude-buildserver.plist"

# Выгружаем старый если был
launchctl unload "$DEST" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST" "$DEST"
launchctl load "$DEST"
echo "✅ Launchd агент установлен и запущен."
echo "   Статус: $(launchctl list | grep claude-buildserver || echo 'загружается...')"
