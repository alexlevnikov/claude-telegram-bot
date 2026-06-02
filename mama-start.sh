#!/usr/bin/env bash
# Запустить бота «Вовка» (для мамы). ЗАПУСКАТЬ ИЗ ОБЫЧНОГО ТЕРМИНАЛА
# (как основной билд-сервер) — claude-TUI нужен живой интерактивный tty.
# Идемпотентно: если бот уже работает, ничего не делает.
#
# Удобный алиас: mama-start   (добавлен в ~/.zshrc)
# Посмотреть бота вживую:     mama-watch
SESSION="claude-mama"

screen -wipe >/dev/null 2>&1
if screen -ls 2>/dev/null | grep -E "\.${SESSION}[[:space:]].*(Detached|Attached)" >/dev/null; then
  echo "✅ Бот «Вовка» уже работает (screen: $SESSION). Посмотреть: mama-watch"
  exit 0
fi

screen -dmS "$SESSION" bash -c "
  export PATH='$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
  export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TERM=xterm-256color
  export TELEGRAM_STATE_DIR='$HOME/.claude/channels/telegram-mama'
  cd '$HOME/Documents/MamaBot'
  exec caffeinate -dimsu claude --channels 'plugin:telegram@claude-plugins-official'
"
echo "✅ Бот «Вовка» запущен (screen: $SESSION). Через ~20с подключится к Telegram."
echo "   Посмотреть вживую: mama-watch   (выход без остановки: Ctrl-a, затем d)"
