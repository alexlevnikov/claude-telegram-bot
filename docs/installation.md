# Установка с нуля

---

## Предварительные требования

### Программное обеспечение

| Инструмент | Версия | Установка |
|---|---|---|
| macOS | 12+ (Monterey) | — |
| `claude` CLI | последняя | `npm install -g @anthropic-ai/claude-code` |
| `bun` | 1.0+ | `curl -fsSL https://bun.sh/install \| bash` |
| `screen` | любая | `brew install screen` |
| `curl` | встроен | — |

Проверка:

```bash
claude --version
bun --version
screen --version
```

### Telegram-боты

Нужно создать **три** бота через [@BotFather](https://t.me/BotFather):

1. **Основной бот** (Claude Build Server) — для задач разработки
2. **Бот Вовка** — для Светланы (можно пропустить если не нужен)
3. **Контрол-бот** — для мониторинга и кнопок

Для каждого бота: `/newbot` → задать имя → получить токен вида `1234567890:AABBcc...`

### Аккаунт Anthropic

- Claude Code CLI должен быть авторизован: `claude --login`
- Достаточный баланс для работы (бот активно использует API)

---

## Шаг 1: Разместить файлы

Все скрипты должны лежать в `~/.claude/buildserver/`:

```bash
mkdir -p ~/.claude/buildserver/state
```

Если клонируете репозиторий:

```bash
cd /путь/к/telegram-bot
cp -r . ~/.claude/buildserver/
```

Или вручную скопировать каждый файл. В итоге должна быть такая структура:

```
~/.claude/buildserver/
├── claude-bot.sh
├── commands.ts
├── tglib.ts
├── launchd-boot.sh
├── install-launchd.sh
├── new-session.sh
├── register-bot-commands.sh
├── on-stop.ts
├── notify-stop.ts
├── compact-check.ts
├── prompt-submitted.ts
├── progress.ts
├── notify-stuck.ts
├── transcribe.sh
├── tts.sh
├── VOICE-INSTRUCTIONS.md
└── com.alexlevnikov.claude-buildserver.plist
```

Сделать скрипты исполняемыми:

```bash
chmod +x ~/.claude/buildserver/*.sh
chmod +x ~/.claude/buildserver/*.ts
```

---

## Шаг 2: Создать конфиги токенов

### Основной бот

```bash
mkdir -p ~/.claude/channels/telegram
cat > ~/.claude/channels/telegram/.env << 'EOF'
TELEGRAM_BOT_TOKEN=ВАШ_ТОКЕН_ОСНОВНОГО_БОТА
EOF
chmod 600 ~/.claude/channels/telegram/.env
```

### Бот Вовка (опционально)

```bash
mkdir -p ~/.claude/channels/telegram-mama
cat > ~/.claude/channels/telegram-mama/.env << 'EOF'
TELEGRAM_BOT_TOKEN=ВАШ_ТОКЕН_ВОВКИ
EOF
chmod 600 ~/.claude/channels/telegram-mama/.env
```

### Контрол-бот

```bash
cat > ~/.claude/buildserver/control.env << 'EOF'
TELEGRAM_CONTROL_BOT_TOKEN=ВАШ_ТОКЕН_КОНТРОЛ_БОТА
EOF
chmod 600 ~/.claude/buildserver/control.env
```

---

## Шаг 3: Настроить allowlist

Нужно узнать свой Telegram `chat_id`. Самый простой способ:

```bash
# Написать любое сообщение основному боту, потом:
curl -s "https://api.telegram.org/bot<ВАШ_ТОКЕН>/getUpdates" | python3 -m json.tool | grep '"id"' | head -5
```

Или написать [@userinfobot](https://t.me/userinfobot) — он ответит вашим ID.

### Allowlist основного бота

```bash
cat > ~/.claude/channels/telegram/access.json << 'EOF'
{
  "allowFrom": ["289326333"]
}
EOF
```

Замените `289326333` на ваш реальный chat_id.

### Allowlist Вовки

```bash
cat > ~/.claude/channels/telegram-mama/access.json << 'EOF'
{
  "allowFrom": ["289326333", "1332813880"]
}
EOF
```

Здесь два ID: Алекс (администратор) и Светлана (хозяйка бота). Порядок не важен — логика определяется по ID в CLAUDE.md.

---

## Шаг 4: Подключить Telegram-плагин

Плагин `plugin:telegram@claude-plugins-official` — это официальный плагин Claude Code для Telegram.

```bash
# Запустить Claude Code интерактивно
claude

# Внутри сессии войти в аккаунт (если ещё не вошли)
/login

# Установить плагин (может уже быть установлен)
# Проверить подключение канала
```

Плагин читает токен из `~/.claude/channels/telegram/.env` автоматически при запуске через `--channels "plugin:telegram@claude-plugins-official"`.

Чтобы убедиться что плагин работает, запустить вручную:

```bash
cd ~/Documents/Projects
BUILD_SERVER=1 claude --channels "plugin:telegram@claude-plugins-official"
```

Написать что-нибудь в Telegram боту — должен ответить.

---

## Шаг 5: Настроить хуки в settings.json {#hooks}

Открыть `~/.claude/settings.json` (создать если не существует) и добавить секцию `hooks`:

```json
{
  "model": "claude-opus-4-5",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bun ~/.claude/buildserver/prompt-submitted.ts"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bun ~/.claude/buildserver/progress.ts"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bun ~/.claude/buildserver/on-stop.ts"
          }
        ]
      }
    ]
  }
}
```

**Важно:** хуки срабатывают при любом запуске Claude Code, не только в режиме бот-сервера. Скрипты проверяют переменную `BUILD_SERVER=1` и молча выходят если она не установлена — это защита от лишних вызовов в обычных сессиях.

---

## Шаг 6: Настроить permissions в settings.json

Для работы билд-сервера нужны расширенные разрешения. Добавить в `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(screen:*)",
      "Bash(bun:*)",
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Bash(grep:*)",
      "Bash(~/.claude/buildserver/*.sh:*)",
      "Bash(~/.claude/buildserver/*.ts:*)"
    ]
  }
}
```

Для полностью автономной работы без постоянных запросов разрешений можно добавить `"Bash(*)"` — но это даёт Claude неограниченный доступ к bash-командам. Решайте сами исходя из уровня доверия.

---

## Шаг 7: Создать CLAUDE.md

### Для основного бота

Создать или дополнить `~/Documents/Projects/CLAUDE.md`. Этот файл содержит инструкции для Claude о том как работать в режиме Telegram-бота.

Минимальное содержание:

```markdown
# Build Server

Ты отвечаешь через Telegram. Терминальный вывод пользователь не видит — 
всегда используй инструмент `reply` для отправки ответа.

## Форматирование
- Короткий ответ без кода → format="text"  
- С кодом → format="markdownv2", код в ``` блоках
```

Полный вариант с меню и командами — см. пример в `~/Documents/Projects/CLAUDE.md` или в разделе [configuration.md](./configuration.md#claude-md).

### Для Вовки

Создать `~/Documents/MamaBot/CLAUDE.md` с персоной и правилами — см. [configuration.md](./configuration.md#mama-claude-md).

---

## Шаг 8: Настроить LaunchD

LaunchD автоматически запускает `launchd-boot.sh` при логине и каждую минуту.

Сначала скопировать plist в buildserver (если ещё не там):

```bash
cp ~/.claude/buildserver/com.alexlevnikov.claude-buildserver.plist \
   ~/.claude/buildserver/com.alexlevnikov.claude-buildserver.plist
```

Отредактировать `BUILD_DIR` в plist если нужно:

```xml
<key>BUILD_DIR</key>
<string>/Users/alexlevnikov/Documents/Projects</string>
```

Заменить `alexlevnikov` на ваше имя пользователя.

Установить и активировать:

```bash
bash ~/.claude/buildserver/install-launchd.sh
```

Проверить:

```bash
launchctl list | grep claude-buildserver
```

Должна появиться строка с `com.alexlevnikov.claude-buildserver`.

---

## Шаг 9: Настроить STT/TTS (опционально)

Если нужна обработка голосовых сообщений:

```bash
cat > ~/.claude/buildserver/transcribe.env << 'EOF'
# Провайдер транскрипции: elevenlabs | openai | mistral
TRANSCRIBE_PROVIDER=openai

# OpenAI Whisper
OPENAI_API_KEY=sk-...
OPENAI_TRANSCRIBE_MODEL=whisper-1

# ElevenLabs Scribe (альтернатива)
# TRANSCRIBE_PROVIDER=elevenlabs
# ELEVENLABS_API_KEY=sk_...
# ELEVENLABS_STT_MODEL=scribe_v2

# TTS (только ElevenLabs)
ELEVENLABS_API_KEY=sk_...
ELEVENLABS_TTS_VOICE=JBFqnCBsd6RMkjVDRZzb
ELEVENLABS_TTS_MODEL=eleven_flash_v2_5
TTS_DAILY_LIMIT_CHARS=50000
EOF
chmod 600 ~/.claude/buildserver/transcribe.env
```

Добавить инструкции по голосу в CLAUDE.md:

```bash
cat ~/.claude/buildserver/VOICE-INSTRUCTIONS.md >> ~/Documents/Projects/CLAUDE.md
```

---

## Шаг 10: Первый запуск

### Запустить боты

```bash
bash ~/.claude/buildserver/claude-bot.sh start
```

### Проверить статус

```bash
bash ~/.claude/buildserver/claude-bot.sh status
```

Ожидаемый вывод:
```
── Статус ботов ──────────────────────────────
  ✅ Билд-сервер  →  screen:claude  (PID 12345)
  ✅ Бот «Вовка»  →  screen:claude-mama  (PID 12346)

── LaunchD агент ─────────────────────────────
  ✅ com.alexlevnikov.claude-buildserver  (загружен)
```

### Зарегистрировать команды в меню Telegram

```bash
bash ~/.claude/buildserver/register-bot-commands.sh
```

### Проверить контрол-бот

```bash
# Посмотреть лог
tail -20 ~/.claude/buildserver/commands.log

# Должно быть что-то вроде:
# commands: @ваш_бот слушает
```

---

## Чеклист после установки

- [ ] `claude-bot.sh status` показывает ✅ для всех компонентов
- [ ] LaunchD агент загружен (`launchctl list | grep claude-buildserver`)
- [ ] Написать основному боту в Telegram — он отвечает
- [ ] Прогресс-индикатор «🤔 Думаю…» появляется при отправке сообщения
- [ ] После ответа появляется уведомление ✅ через контрол-бот с кнопками
- [ ] `/status` в Telegram отображает корректную информацию
- [ ] (Если настроили голос) Голосовое сообщение транскрибируется и Claude отвечает
- [ ] Перезагрузить Mac — боты поднялись автоматически

---

## Полезные алиасы (опционально)

Добавить в `~/.zshrc` или `~/.bashrc`:

```bash
# Управление билд-сервером
alias bs='~/.claude/buildserver/claude-bot.sh'
alias bss='~/.claude/buildserver/claude-bot.sh status'
alias bsr='~/.claude/buildserver/claude-bot.sh restart'

# Подключиться к экрану
alias bsa='screen -r claude'
alias mama='screen -r claude-mama'

# Логи контрол-бота
alias bsl='tail -f ~/.claude/buildserver/commands.log'
```

---

## Установка только для Вовки (без основного бота)

Если нужен только бот Вовка:

```bash
# Создать директорию MamaBot
mkdir -p ~/Documents/MamaBot

# Создать settings.json для Вовки
cat > ~/Documents/MamaBot/.claude/settings.json << 'EOF'
{
  "model": "claude-sonnet-4-5",
  "permissions": {
    "allow": [
      "mcp__plugin_telegram_telegram__reply",
      "mcp__plugin_telegram_telegram__react",
      "mcp__plugin_telegram_telegram__download_attachment",
      "Bash(~/.claude/buildserver/transcribe.sh:*)",
      "Bash(~/.claude/buildserver/tts.sh:*)",
      "Bash(~/.claude/buildserver/new-session.sh:*)"
    ]
  }
}
EOF

# Запустить только Вовку
bash ~/.claude/buildserver/claude-bot.sh restart-mama
```

---

## Обновление

```bash
# Остановить боты
bash ~/.claude/buildserver/claude-bot.sh stop

# Скопировать новые файлы
cp /путь/к/новым/файлам/* ~/.claude/buildserver/

# Запустить снова
bash ~/.claude/buildserver/claude-bot.sh start
bash ~/.claude/buildserver/register-bot-commands.sh
```

Если изменились хуки в `settings.json` — они применятся автоматически при следующем старте Claude Code.
