#!/usr/bin/env bash
# Открывается в окне Terminal (через `open -a Terminal`), поэтому имеет живой tty,
# который нужен TUI claude. Идемпотентно поднимает бота «Вовка» в screen-сессии
# claude-mama.
#
# ВАЖНО: это окно НЕ закрываем автоматически. Если закрыть окно сразу, claude в
# detached-screen перестаёт нормально работать (канал отваливается). Окно можно
# просто СВЕРНУТЬ — бот продолжает работать в фоне. Подключиться к нему: mama-watch

SESSION="claude-mama"
screen -wipe >/dev/null 2>&1

if screen -ls 2>/dev/null | grep -E "\.${SESSION}[[:space:]].*(Detached|Attached)" >/dev/null; then
  echo "✅ Бот «Вовка» уже работает (screen: $SESSION)."
else
  screen -dmS "$SESSION" bash -c "
    export PATH='$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TERM=xterm-256color
    export TELEGRAM_STATE_DIR='$HOME/.claude/channels/telegram-mama'
    cd '$HOME/Documents/MamaBot'
    exec caffeinate -dimsu claude --channels 'plugin:telegram@claude-plugins-official'
  "
  echo "✅ Бот «Вовка» запущен (screen: $SESSION)."
fi

echo
echo "Это окно можно СВЕРНУТЬ — бот работает в фоне."
echo "Посмотреть бота вживую:  mama-watch    (выход без остановки: Ctrl-a, затем d)"
