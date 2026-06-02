#!/usr/bin/env bash
# Запускается launchd при логине и периодически (StartInterval).
# claude — это TUI, которому нужен НАСТОЯЩИЙ терминал; launchd его не даёт.
# Поэтому здесь только ПРОВЕРКА (без tty): жив ли бот «Вовка» в screen-сессии
# claude-mama. Если жив — ничего не делаем (окно не открывается). Если нет —
# открываем окно Terminal, которое поднимет бота в screen (там есть tty).
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SESSION="claude-mama"
screen -wipe >/dev/null 2>&1

# Жив (Detached/Attached) — выходим, окно не открываем.
if screen -ls 2>/dev/null | grep -E "\.${SESSION}[[:space:]].*(Detached|Attached)" >/dev/null; then
  exit 0
fi

# Бот не запущен — открываем Terminal (нужен живой tty), он поднимет бота в screen.
/usr/bin/open -a Terminal "$HOME/.claude/buildserver/mama-boot.command"
