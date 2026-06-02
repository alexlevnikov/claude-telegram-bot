# Claude Telegram Build Server

Система из двух Telegram-ботов, которая позволяет управлять Claude Code и получать
уведомления о завершении задач прямо в Telegram.

## Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│  Telegram                                                   │
│  ┌─────────────────────┐  ┌──────────────────────────────┐  │
│  │  Claude Bot         │  │  Control Bot                 │  │
│  │  (claude-plugins)   │  │  (commands.ts)               │  │
│  │  Принимает задачи,  │  │  Кнопки управления,          │  │
│  │  отвечает напрямую  │  │  уведомления о стопе,        │  │
│  │                     │  │  статус, логи, проекты       │  │
│  └─────────────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         ↕                            ↕
┌─────────────────────────────────────────────────────────────┐
│  Mac (screen-сессия "claude")                               │
│  Claude Code CLI  ←→  screen ← commands.ts инжектирует     │
│                                                             │
│  Хуки Claude:                                               │
│    UserPromptSubmit → prompt-submitted.ts  (индикатор 🤔)  │
│    PostToolUse      → progress.ts          (прогресс 📖)   │
│    Stop             → on-stop.ts → notify-stop.ts + compact │
│                                                             │
│  launchd-boot.sh (каждую минуту) → авто-recovery           │
└─────────────────────────────────────────────────────────────┘
```

**Claude Bot** — основной канал: пользователь пишет задачи, Claude отвечает.  
**Control Bot** — управляющий: кнопки ▶/🔁/🛑, статус, логи, список проектов.

---

## Что нужно заранее

- **Bun** (`curl -fsSL https://bun.sh/install | bash`)
- **Claude Code CLI** (`npm install -g @anthropic/claude-code`)
- **GNU Screen** (`brew install screen`)
- Два Telegram-бота от @BotFather:
  1. **Claude Bot** — основной, его токен в `~/.claude/channels/telegram/.env`
  2. **Control Bot** — управляющий, его токен в `~/.claude/buildserver/control.env`

---

## Установка с нуля

### 1. Скопировать файлы на место

```bash
cp -r . ~/.claude/buildserver
chmod +x ~/.claude/buildserver/*.sh ~/.claude/buildserver/*.command
```

### 2. Создать конфиги

**Основной бот (Claude channel):**
```bash
mkdir -p ~/.claude/channels/telegram
echo "TELEGRAM_BOT_TOKEN=<токен-основного-бота>" > ~/.claude/channels/telegram/.env
```

**Control Bot:**
```bash
cp control.env.example ~/.claude/buildserver/control.env
# Отредактируй: вставь TELEGRAM_CONTROL_BOT_TOKEN
nano ~/.claude/buildserver/control.env
```

**Голос/TTS (опционально):**
```bash
cp transcribe.env.example ~/.claude/buildserver/transcribe.env
# Отредактируй: вставь API-ключи
nano ~/.claude/buildserver/transcribe.env
```

### 3. Настроить access.json — кто может писать боту

```bash
# Узнать свой Telegram ID: написать @userinfobot
cat > ~/.claude/channels/telegram/access.json << 'EOF'
{
  "allowFrom": ["123456789"]
}
EOF
```

### 4. Прописать хуки в Claude Code

```bash
claude /settings
```

Или отредактировать `~/.claude/settings.json` вручную — добавить в секцию `hooks`:

```json
"hooks": {
  "UserPromptSubmit": [{
    "hooks": [{"type": "command",
      "command": "/Users/ИМЯ/.bun/bin/bun /Users/ИМЯ/.claude/buildserver/prompt-submitted.ts"}]
  }],
  "PostToolUse": [{
    "hooks": [{"type": "command",
      "command": "/Users/ИМЯ/.bun/bin/bun /Users/ИМЯ/.claude/buildserver/progress.ts"}]
  }],
  "Stop": [{
    "hooks": [{"type": "command",
      "command": "/Users/ИМЯ/.bun/bin/bun /Users/ИМЯ/.claude/buildserver/on-stop.ts"}]
  }]
}
```

### 5. Установить LaunchD агент (авто-запуск при логине)

Отредактируй пути в `com.alexlevnikov.claude-buildserver.plist` под своего пользователя,
потом:

```bash
~/.claude/buildserver/install-launchd.sh
```

Агент будет запускаться при логине и каждую минуту проверять жизнь screen-сессии.

### 6. Добавить алиасы в ~/.zshrc

```bash
CLAUDE_BOT="$HOME/Documents/Projects/telegram-bot/claude-bot.sh"

alias start_claude_bot='$CLAUDE_BOT start'
alias stop_claude_bot='$CLAUDE_BOT stop'
alias claude-bot-status='$CLAUDE_BOT status'
alias claude-bot-restart='$CLAUDE_BOT restart'
alias claude-watch='screen -r claude'
alias mama-watch='screen -d -r claude-mama'
```

После этого: `source ~/.zshrc`

### 7. Включить Telegram-плагин в Claude Code

```bash
claude /login
# В настройках включить: plugin:telegram@claude-plugins-official
```

---

## Запуск и остановка

Все команды управления собраны в одном скрипте `claude-bot.sh`.

### Быстрый старт

```bash
start_claude_bot
```

Запускает билд-сервер (screen: `claude`) и бота «Вовка» (screen: `claude-mama`),
если у него есть токен и рабочая папка. Идемпотентно — безопасно вызывать повторно.

### Остановка

```bash
stop_claude_bot
```

Останавливает обе screen-сессии, убивает фоновые хуки (`bun`), чистит
временные прогресс-файлы и флаг stuck-детектора.

### Другие команды

```bash
claude-bot-restart   # стоп → старт
claude-bot-status    # статус обоих ботов + LaunchD + stuck-детектор
```

### Напрямую через скрипт

```bash
~/Documents/Projects/telegram-bot/claude-bot.sh start
~/Documents/Projects/telegram-bot/claude-bot.sh stop
~/Documents/Projects/telegram-bot/claude-bot.sh restart
~/Documents/Projects/telegram-bot/claude-bot.sh status
```

### Подключиться и смотреть вживую

```bash
claude-watch       # подключиться к билд-серверу
mama-watch         # подключиться к боту «Вовка»
# Выйти без остановки: Ctrl-a, затем d
```

---

## Как пользоваться

После запуска откройте Control Bot в Telegram. Появится главное меню с кнопками.

### Telegram-команды (Control Bot)

| Команда | Что делает |
|---------|------------|
| `/status` | Статус сессии, последний стоп, расход TTS |
| `/logs` | Последние 30 строк экрана Claude |
| `/projects` | Список проектов в BUILD_DIR |
| `/sessions` | Сохранённые сессии |
| `/system` | Системная информация |
| `/ping` | Быстрая проверка связи |
| `/model` | Переключение модели Sonnet/Opus/Haiku |

### Inline-кнопки после каждого ответа

После завершения хода Claude Control Bot присылает уведомление с кнопками:
- **▶ Продолжить** — инжектировать пустой Enter (продолжить работу)
- **🔁 Повторить** — инжектировать `/retry`
- **🛑 Стоп** — отправить Escape (прервать текущую операцию)

### Отправить задачу напрямую

Пиши задачи через **основной Claude Bot** — сообщения напрямую попадают в контекст
Claude Code. Если хочешь переключить рабочую папку — используй кнопку Projects в меню.

### Голосовые сообщения

Отправь голосовое сообщение в Claude Bot — оно автоматически транскрибируется через
STT и передаётся Claude как текст. Claude может ответить голосом через TTS.

---

## Как убить застрявшие серверы

### Через алиас (рекомендуется)

```bash
stop_claude_bot
```

Делает всё разом: останавливает screen, убивает хуки, чистит временные файлы.

### Вручную — screen

```bash
# Список всех screen-сессий
screen -ls

# Убить конкретную сессию
screen -S claude -X quit
screen -S claude-mama -X quit

# Убить все мёртвые сессии (сокеты)
screen -wipe

# Убить все сессии claude* разом
screen -ls | grep '\.claude' | awk '{print $1}' | xargs -I{} screen -S {} -X quit
```

### Вручную — по PID (если screen не реагирует)

```bash
# screen -ls покажет: 12345.claude (Detached)
kill 12345
# Если не реагирует:
kill -9 12345
```

### Вручную — хуки bun

```bash
pkill -f "buildserver/on-stop.ts"
pkill -f "buildserver/prompt-submitted"
pkill -f "buildserver/progress.ts"
pkill -f "buildserver/compact-check"
```

### LaunchD агент

```bash
# Статус
launchctl list | grep claude-buildserver

# Выгрузить (остановит авто-recovery)
launchctl unload ~/Library/LaunchAgents/com.alexlevnikov.claude-buildserver.plist

# Перезагрузить
launchctl unload ~/Library/LaunchAgents/com.alexlevnikov.claude-buildserver.plist 2>/dev/null
launchctl load  ~/Library/LaunchAgents/com.alexlevnikov.claude-buildserver.plist
```

### Диагностика зависания

```bash
# Логи launchd (авто-recovery)
tail -50 ~/.claude/buildserver/launchd.err.log

# Проверить stuck-флаг
ls -la ~/.claude/buildserver/state/prompt-active.json
# Если существует и старше 15 мин — Claude завис

# Смотреть экран вживую
claude-watch   # Ctrl-a, d — выйти без остановки
```

---

## Бот «Вовка» (Mama Bot)

Отдельный изолированный инстанс Claude Code с отдельным токеном и рабочей папкой.

**Конфиг:** `~/.claude/channels/telegram-mama/.env` — TELEGRAM_BOT_TOKEN  
**Рабочая папка:** `~/Documents/MamaBot`

```bash
start_claude_bot      # запускает оба бота, включая «Вовку»
stop_claude_bot       # останавливает оба

mama-watch            # подключиться к screen claude-mama

# Автозапуск через Terminal (нужен живой tty):
open -a Terminal ~/.claude/buildserver/mama-boot.command
```

---

## Структура файлов

```
~/.claude/buildserver/            ← рабочая копия (живые конфиги + логи)
~/.claude/channels/telegram/      ← токен + access.json основного бота
~/.claude/channels/telegram-mama/ ← токен + access.json бота «Вовка»

~/Documents/Projects/telegram-bot/ ← этот репозиторий (исходники)
```

| Файл | Назначение |
|------|------------|
| `claude-bot.sh` | **Единый скрипт управления** (start / stop / restart / status) |
| `commands.ts` | Control Bot — Telegram-меню, кнопки управления |
| `tglib.ts` | Общие хелперы для Telegram API (токены, send, api) |
| `on-stop.ts` | Оркестратор Stop-хуков Claude |
| `notify-stop.ts` | Уведомление в Telegram по завершении хода |
| `compact-check.ts` | Авто-compact при заполнении контекста |
| `prompt-submitted.ts` | UserPromptSubmit: индикатор 🤔 + stuck-трекинг |
| `progress.ts` | PostToolUse: live-прогресс через edit_message |
| `notify-stuck.ts` | Алерт когда Claude не отвечает >15 мин |
| `launchd-boot.sh` | Идемпотентный запуск / авто-recovery для launchd |
| `install-launchd.sh` | Установить plist в LaunchAgents и активировать |
| `transcribe.sh` | STT: голос → текст (ElevenLabs / OpenAI / Mistral) |
| `tts.sh` | TTS: текст → голос (ElevenLabs Flash) |
| `VOICE-INSTRUCTIONS.md` | Инструкция для Claude как обрабатывать голос |
| `mama-*.sh / mama-boot.command` | Всё для бота «Вовка» |
| `control.env.example` | Шаблон токена control-бота |
| `transcribe.env.example` | Шаблон ключей STT/TTS |
| `com.alexlevnikov.claude-buildserver.plist` | LaunchD агент |

---

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `BUILD_SERVER` | — | Должна быть `1` для активации хуков |
| `TMUX_SESSION` | `claude` | Имя screen-сессии |
| `BUILD_DIR` | `~/Documents/Projects` | Рабочая папка Claude |
| `STUCK_MINUTES` | `15` | Через сколько минут считать Claude зависшим |
| `COMPACT_THRESHOLD` | `75` | % заполнения контекста для авто-compact |
| `TELEGRAM_STATE_DIR` | `~/.claude/channels/telegram` | Папка с токеном и access.json |

---

## Алиасы (~/.zshrc)

| Алиас | Действие |
|-------|----------|
| `start_claude_bot` | Запустить все боты |
| `stop_claude_bot` | Остановить все боты |
| `claude-bot-restart` | Перезапустить все боты |
| `claude-bot-status` | Статус ботов, LaunchD, stuck-детектор |
| `claude-watch` | Подключиться к screen билд-сервера |
| `mama-watch` | Подключиться к screen бота «Вовка» |
