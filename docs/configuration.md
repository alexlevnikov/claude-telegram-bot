# Конфигурация

Описание всех конфигурационных файлов, переменных окружения и настроек системы.

---

## Конфигурационные файлы

### `~/.claude/channels/telegram/.env`

Токен основного Telegram-бота. Читается плагином `plugin:telegram` и библиотекой `tglib.ts`.

```bash
TELEGRAM_BOT_TOKEN=1234567890:AABBCCDDEEFFaabbccddeeff-1234567890
```

Права доступа: `chmod 600` (только владелец).

### `~/.claude/channels/telegram-mama/.env`

Токен бота Вовки. Такой же формат.

```bash
TELEGRAM_BOT_TOKEN=9876543210:ZZYYXXWWVVUUzzyyxxwwvvuu-9876543210
```

### `~/.claude/channels/telegram/access.json`

Список chat_id, которым разрешено общаться с основным ботом. Используется плагином для фильтрации входящих сообщений, и `tglib.ts` для определения кому отправлять уведомления.

```json
{
  "allowFrom": ["289326333"]
}
```

Значение `allowFrom` — массив строк, не чисел. Добавить несколько пользователей:

```json
{
  "allowFrom": ["289326333", "1234567890"]
}
```

### `~/.claude/channels/telegram-mama/access.json`

Allowlist для Вовки. Обычно содержит два ID: Светлану и Алекса.

```json
{
  "allowFrom": ["1332813880", "289326333"]
}
```

Порядок не важен. Логика определения ролей (кто Светлана, кто Алекс) задаётся в `CLAUDE.md` по числовым значениям ID.

### `~/.claude/buildserver/control.env`

Токен контрол-бота. Используется `tglib.ts` (`loadControlToken()`) и контрол-ботом `commands.ts`.

```bash
TELEGRAM_CONTROL_BOT_TOKEN=1111111111:CCDDEEFFGGHHccddeeffgghh-1111111111
```

Пример файла в репозитории: `control.env.example`.

### `~/.claude/buildserver/transcribe.env`

Ключи для STT и TTS. Используется скриптами `transcribe.sh` и `tts.sh`.

```bash
# ── STT (транскрипция голоса) ────────────────────────────────────────────────
# Выбор провайдера: elevenlabs | openai | mistral
TRANSCRIBE_PROVIDER=openai

# OpenAI Whisper
OPENAI_API_KEY=sk-proj-...
OPENAI_TRANSCRIBE_MODEL=whisper-1

# ElevenLabs Scribe (альтернативный провайдер)
ELEVENLABS_API_KEY=sk_...
ELEVENLABS_STT_MODEL=scribe_v2

# Mistral Voxtral
MISTRAL_API_KEY=...
MISTRAL_TRANSCRIBE_MODEL=voxtral-mini-latest

# ── TTS (генерация голоса) ────────────────────────────────────────────────────
# Только ElevenLabs Flash
ELEVENLABS_TTS_VOICE=JBFqnCBsd6RMkjVDRZzb   # voice_id (George — многоязычный)
ELEVENLABS_TTS_MODEL=eleven_flash_v2_5        # Flash: задержка 75ms, 32 языка
TTS_DAILY_LIMIT_CHARS=50000                   # дневной лимит символов (~$2.50)
```

Пример файла: `transcribe.env.example`.

### `~/.claude/settings.json`

Глобальные настройки Claude Code. Здесь живут хуки, модель, разрешения.

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
  },
  "permissions": {
    "allow": [
      "Bash(screen:*)",
      "Bash(bun:*)",
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(~/.claude/buildserver/*.sh:*)"
    ]
  }
}
```

### `~/Documents/MamaBot/.claude/settings.json`

Отдельные настройки только для Вовки. Переопределяют глобальные когда Claude Code запускается из директории `MamaBot`.

```json
{
  "model": "claude-sonnet-4-5",
  "permissions": {
    "allow": [
      "mcp__plugin_telegram_telegram__reply",
      "mcp__plugin_telegram_telegram__react",
      "mcp__plugin_telegram_telegram__download_attachment",
      "Bash(~/.claude/buildserver/transcribe.sh:*)",
      "Bash(~/.claude/buildserver/tts.sh:*)",
      "Bash(~/.claude/buildserver/new-session.sh mama:*)",
      "Bash(screen -S claude-mama:*)"
    ]
  }
}
```

Вовка использует `sonnet` вместо `opus` — достаточно для бытовых задач, дешевле.

---

## Переменные окружения

### Переменные запуска (`claude-bot.sh`)

| Переменная | По умолчанию | Описание |
|---|---|---|
| `BUILD_SERVER` | `1` | Активирует хуки. Без этой переменной хуки молча выходят ничего не делая. |
| `TMUX_SESSION` | `claude` | Имя screen-сессии. Используется хуками для инжекции команд через `screen -S`. |
| `BUILD_DIR` | `~/Documents/Projects` | Рабочая директория для основного бота. Claude будет работать в этом cwd. |
| `COMPACT_THRESHOLD` | `35` | Порог compact в процентах (0–100). При заполнении контекста на это значение — автоматически запускается `/compact`. |
| `CLEAR_THRESHOLD` | `80` | Порог clear. При превышении — `/clear`. Должен быть больше `COMPACT_THRESHOLD`. |

### Переменные для Вовки

| Переменная | Значение | Описание |
|---|---|---|
| `TELEGRAM_STATE_DIR` | `~/.claude/channels/telegram-mama` | Переопределяет откуда `tglib.ts` читает токен и access.json. |
| `TMUX_SESSION` | `claude-mama` | Имя screen-сессии Вовки. |

### Переменные watchdog (`launchd-boot.sh`)

| Переменная | По умолчанию | Описание |
|---|---|---|
| `STUCK_MINUTES` | `15` | Сколько минут без ответа считается зависанием. После этого — алерт в Telegram. |

Эти переменные можно задать в plist-файле:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>BUILD_DIR</key>
    <string>/Users/alexlevnikov/Documents/Projects</string>
    <key>TMUX_SESSION</key>
    <string>claude</string>
    <key>STUCK_MINUTES</key>
    <string>20</string>
    <key>COMPACT_THRESHOLD</key>
    <string>40</string>
    <key>CLEAR_THRESHOLD</key>
    <string>75</string>
</dict>
```

### Переменные TTS

| Переменная | По умолчанию | Описание |
|---|---|---|
| `TRANSCRIBE_PROVIDER` | `openai` | STT-провайдер: `elevenlabs`, `openai`, `mistral`. |
| `ELEVENLABS_TTS_VOICE` | `JBFqnCBsd6RMkjVDRZzb` | Voice ID в ElevenLabs. George — multilingual, хорошо говорит по-русски. |
| `ELEVENLABS_TTS_MODEL` | `eleven_flash_v2_5` | Модель TTS. Flash v2.5 — 75ms задержка, 32 языка. |
| `TTS_DAILY_LIMIT_CHARS` | `50000` | Дневной лимит символов. При превышении TTS возвращает exit code 3. |

---

## LaunchD plist

Файл: `~/.claude/buildserver/com.alexlevnikov.claude-buildserver.plist`

После установки копируется в `~/Library/LaunchAgents/`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Идентификатор агента -->
    <key>Label</key>
    <string>com.alexlevnikov.claude-buildserver</string>

    <!-- Команда для запуска -->
    <key>ProgramArguments</key>
    <array>
        <string>/Users/alexlevnikov/.claude/buildserver/launchd-boot.sh</string>
    </array>

    <!-- Запускать при входе в систему -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Повторять каждые 60 секунд -->
    <key>StartInterval</key>
    <integer>60</integer>

    <!-- Переменные окружения для скрипта -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>BUILD_DIR</key>
        <string>/Users/alexlevnikov/Documents/Projects</string>
        <key>TMUX_SESSION</key>
        <string>claude</string>
    </dict>

    <!-- Лог-файлы -->
    <key>StandardOutPath</key>
    <string>/Users/alexlevnikov/.claude/buildserver/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/alexlevnikov/.claude/buildserver/launchd.err.log</string>
</dict>
</plist>
```

**Ключевые параметры:**

| Параметр | Значение | Описание |
|---|---|---|
| `RunAtLoad` | `true` | Запускать сразу при загрузке launchd (при логине) |
| `StartInterval` | `60` | Повторять каждые N секунд |
| `StandardOutPath` | путь к .log | Куда пишет stdout `launchd-boot.sh` |
| `StandardErrorPath` | путь к .log | Куда пишет stderr (там логи о перезапусках) |

---

## Структура CLAUDE.md {#claude-md}

### Основной бот (`~/Documents/Projects/CLAUDE.md`)

Ключевые секции:

```markdown
# Build Server — инструкции для Claude

## Telegram: правила форматирования ответов

Ты отвечаешь пользователю через Telegram. Терминальный вывод не виден —
всегда используй инструмент `reply` для отправки ответа.

### Форматирование
- Короткий ответ без кода → reply(format="text")
- С кодом → reply(format="markdownv2")
  - В MarkdownV2 экранировать: . ! ( ) [ ] { } + - = | > # ~

## Голосовые сообщения

Когда attachment_kind="voice":
1. download_attachment → путь
2. ~/.claude/buildserver/transcribe.sh "<путь>" → текст
3. Работать с текстом как с обычным запросом

Голосовой ответ — только если: голосовой вход + < 500 символов + нет кода:
  ~/.claude/buildserver/tts.sh "<текст>" → путь к .ogg

## Меню и команды

/menu, /start, /help → показать reply keyboard с кнопками
📊 Статус | 📋 Логи | 🗜 Compact | 🧹 Clear | 🆕 Новая сессия | 🤖 Модель | 📁 Проекты | ❓ Помощь

(полная логика кнопок — в CLAUDE.md проекта)

## Сборка проектов

- Никогда не делать git push без явной команды
- Перед коммитом — тесты и линт
- При ошибках — сначала диагностика
```

### Вовка (`~/Documents/MamaBot/CLAUDE.md`) {#mama-claude-md}

Ключевые секции:

```markdown
# Вовка — личный помощник

## ⚠️ Telegram: только через reply tool

## Персона

Ты — Вовка из мультфильма «Вовка в Тридевятом царстве».
Тёплый, простой, любознательный. Общаешься с пожилой женщиной.
Никакого жаргона. Коротко и по делу.

## Кто пишет (роли)

- 1332813880 — Светлана (хозяйка, основной режим)
- 289326333  — Алекс (администратор, деловой тон)

## Память

Активно записывай и перечитывай память:
- Имя, семья, важные даты, здоровье, предпочтения
- Начинай каждый разговор со сверки памяти

## Голос и текст

(аналогично основному боту)

## Алерты Алексу

При важных событиях (Светлана растеряна, здоровье, деньги, ошибка) —
отправить Алексу (chat_id 289326333) отдельное краткое сообщение.

## Чего не делать

- Не показывать технические детали Светлане
- Не грузить её жаргоном
- Не делать необратимого без явной просьбы
```

---

## Настройка модели

Текущая модель задаётся в `~/.claude/settings.json`:

```json
{
  "model": "claude-opus-4-5"
}
```

Варианты:
- `claude-haiku-4-5` — быстрый и дешёвый, для простых задач
- `claude-sonnet-4-5` — баланс скорости и качества (используется для Вовки)
- `claude-opus-4-5` — максимальное качество, дороже (рекомендуется для основного бота)

Через Telegram можно менять модель на лету кнопкой 🤖 Модель — изменения записываются в `settings.json` и применяются при следующем запуске.

---

## Файлы состояния

Хуки и watchdog используют файлы состояния в `~/.claude/buildserver/state/`:

| Файл | Создаётся | Удаляется | Назначение |
|---|---|---|---|
| `prompt-active.json` | `prompt-submitted.ts` при каждом промпте | `notify-stop.ts` при Stop | Stuck-детектор: если файл старый — Claude завис |
| `prompt-active.alerted` | `launchd-boot.sh` после отправки алерта | `notify-stop.ts` при Stop | Предотвращает повторные алерты при одном зависании |
| `last-stop.txt` | `notify-stop.ts` | Не удаляется | Дата/время последнего ответа Claude (для `/status`) |
| `tts-usage.json` | `tts.sh` | Старые записи чистятся автоматически | Трекинг дневного расхода TTS |
| `commands.pid` | `launchd-boot.sh` | Не удаляется | PID контрол-бота для проверки живости |

Временные файлы в `/tmp/`:

| Файл | Создаётся | Удаляется | Назначение |
|---|---|---|---|
| `claude-tg-progress-<chatId>.json` | `prompt-submitted.ts` | `notify-stop.ts` | ID сообщения прогресса для редактирования |
| `claude-tts-<timestamp>-<random>.ogg` | `tts.sh` | Нет (вручную или ОС) | Сгенерированный голосовой ответ |
| `.stop-payload-<timestamp>.json` | `on-stop.ts` | `on-stop.ts` после завершения | Временный файл для передачи payload между хуками |

---

## Регистрация команд Telegram

Скрипт `register-bot-commands.sh` регистрирует список команд через `setMyCommands` API. Это то меню, которое появляется когда пользователь нажимает `/` в Telegram.

### Основной бот

```
/status     📊 Статус сессии, модель, последний ответ
/logs       📋 Последние 20 строк экрана
/compact    🗜 Сжать контекст — сохранить суть, освободить память
/clear      🧹 Очистить контекст полностью
/newsession 🆕 Новая сессия — полный сброс контекста и истории
/model      🤖 Показать / сменить модель (haiku / sonnet / opus)
/projects   📁 Список проектов
/help       ❓ Все команды
```

### Бот Вовка (только для Алекса)

```
/status     📊 Статус сессии Вовки
/compact    🗜 Сжать контекст
/newsession 🆕 Новая сессия — сброс контекста
/help       ❓ Команды администратора
```

Команды нужно перерегистрировать после каждого перезапуска сессии — плагин сбрасывает их на дефолтные. `new-session.sh` делает это автоматически.

```bash
# Зарегистрировать для обоих ботов
bash ~/.claude/buildserver/register-bot-commands.sh

# Только для основного бота
bash ~/.claude/buildserver/register-bot-commands.sh main

# Только для Вовки
bash ~/.claude/buildserver/register-bot-commands.sh mama
```
