#!/usr/bin/env bash
# Регистрирует команды в меню Telegram-ботов (тот список что появляется при /).
# Запускать один раз после настройки токенов, или после добавления новых команд.
#
# Использование:
#   ./register-bot-commands.sh          — оба бота
#   ./register-bot-commands.sh main     — только билд-сервер
#   ./register-bot-commands.sh mama     — только Вовка

set -euo pipefail
export PATH="$HOME/.bun/bin:$PATH"
TARGET="${1:-all}"

tg_set_commands() {
  local token="$1"
  local commands_json="$2"
  local label="$3"
  local resp
  resp=$(curl -fsS "https://api.telegram.org/bot${token}/setMyCommands" \
    -H "Content-Type: application/json" \
    -d "{\"commands\": ${commands_json}}")
  if echo "$resp" | grep -q '"ok":true'; then
    echo "  ✅ $label — команды зарегистрированы"
  else
    echo "  ❌ $label — ошибка: $resp"
  fi
}

load_token() {
  local env_file="$1"
  local var="$2"
  [ -f "$env_file" ] || { echo "  ⚠️  не найден: $env_file"; return 1; }
  grep "^${var}=" "$env_file" | head -1 | cut -d= -f2-
}

# ── Команды для билд-сервера ────────────────────────────────────────────────
MAIN_COMMANDS='[
  {"command": "status",     "description": "📊 Статус сессии, модель, последний ответ"},
  {"command": "logs",       "description": "📋 Последние 20 строк экрана"},
  {"command": "compact",    "description": "🗜 Сжать контекст — сохранить суть, освободить память"},
  {"command": "clear",      "description": "🧹 Очистить контекст полностью"},
  {"command": "newsession", "description": "🆕 Новая сессия — полный сброс контекста и истории"},
  {"command": "model",      "description": "🤖 Показать / сменить модель (haiku / sonnet / opus)"},
  {"command": "projects",   "description": "📁 Список проектов"},
  {"command": "help",       "description": "❓ Все команды"}
]'

# ── Команды для Вовки (только для Алекса — Светлана не открывает /) ─────────
MAMA_COMMANDS='[
  {"command": "status",     "description": "📊 Статус сессии Вовки"},
  {"command": "compact",    "description": "🗜 Сжать контекст"},
  {"command": "newsession", "description": "🆕 Новая сессия — сброс контекста"},
  {"command": "help",       "description": "❓ Команды администратора"}
]'

if [ "$TARGET" = "all" ] || [ "$TARGET" = "main" ]; then
  TOKEN=$(load_token "$HOME/.claude/channels/telegram/.env" "TELEGRAM_BOT_TOKEN") || true
  if [ -n "$TOKEN" ]; then
    tg_set_commands "$TOKEN" "$MAIN_COMMANDS" "Билд-сервер"
  else
    echo "  ⚠️  Билд-сервер: токен не найден в ~/.claude/channels/telegram/.env"
  fi
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "mama" ]; then
  TOKEN=$(load_token "$HOME/.claude/channels/telegram-mama/.env" "TELEGRAM_BOT_TOKEN") || true
  if [ -n "$TOKEN" ]; then
    tg_set_commands "$TOKEN" "$MAMA_COMMANDS" "Вовка"
  else
    echo "  ⚠️  Вовка: токен не найден в ~/.claude/channels/telegram-mama/.env"
  fi
fi
