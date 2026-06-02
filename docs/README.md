# Claude Telegram Build Server — документация

Система из двух Telegram-ботов на базе Claude Code для удалённого управления задачами разработки и личной помощи с Mac.

---

## Что это такое

**Claude Telegram Build Server** — обёртка вокруг Claude Code CLI, превращающая его в постоянно работающего Telegram-ассистента. Вы пишете задачу в Telegram — Claude выполняет её прямо на вашем Mac: читает и редактирует файлы, запускает команды, делает git-коммиты, собирает проекты. Ответ приходит обратно в Telegram с прогрессом в реальном времени.

Дополнительно работает изолированный бот **Вовка** — личный помощник для нетехнического пользователя (пожилой женщины) с тёплой персоной и памятью о хозяйке.

---

## Быстрая архитектура

```
 Telegram                          Mac
─────────────────────────────────────────────────────────────────────

  Пользователь                  screen "claude"
       │   ──── сообщение ─────►  Claude Code CLI
       │                         │  plugin:telegram (основной бот)
       │   ◄── ответ ──────────  │
       │                         │
       │   ◄── прогресс ────────  PostToolUse hook → progress.ts
       │                         │
       │   ◄── 🤔 Думаю… ───────  UserPromptSubmit hook → prompt-submitted.ts
       │
  Алекс / Светлана              screen "claude-mama"
       │   ──── сообщение ─────►  Claude Code CLI
       │                         │  plugin:telegram-mama (бот Вовка)
       │   ◄── ответ ──────────  │
       │
  Контрол-бот ◄──── Stop hook ── on-stop.ts → notify-stop.ts
  (отдельный                  │                compact-check.ts
   токен)                     │
                               │
  launchd ─── каждые 60 сек ─► launchd-boot.sh
                                 ├── ensure контрол-бот жив
                                 ├── stuck detection
                                 └── авто-recovery screen-сессий
```

---

## Компоненты

| Компонент | Описание |
|---|---|
| **Основной бот** | Claude Code в screen `claude`, cwd = `~/Documents/Projects` |
| **Бот Вовка** | Claude Code в screen `claude-mama`, cwd = `~/Documents/MamaBot` |
| **Контрол-бот** | Лёгкий Bun-процесс (`commands.ts`), мониторинг и кнопки |
| **Хуки** | `prompt-submitted.ts`, `progress.ts`, `on-stop.ts` |
| **Watchdog** | `launchd-boot.sh` каждые 60 сек |
| **Голос** | `transcribe.sh` (STT) + `tts.sh` (TTS) |

---

## Документация

| Файл | Содержание |
|---|---|
| [architecture.md](./architecture.md) | Полная архитектура, поток данных, жизненный цикл |
| [installation.md](./installation.md) | Пошаговая установка с нуля |
| [configuration.md](./configuration.md) | Все конфиги, переменные окружения, настройки |
| [bots.md](./bots.md) | Использование ботов — команды, кнопки, примеры |
| [context-management.md](./context-management.md) | Управление контекстом, compact/clear, стоимость |
| [monitoring.md](./monitoring.md) | Мониторинг, watchdog, stuck-детектор, алерты |
| [troubleshooting.md](./troubleshooting.md) | Устранение неполадок, ядерный сброс |

---

## 5-минутный быстрый старт

Предполагается, что у вас уже есть:
- macOS с установленными `bun`, `claude` CLI, `screen`
- Два Telegram-бота (основной + Вовка) от [@BotFather](https://t.me/BotFather)
- Третий бот для контрол-бота

### 1. Скопировать файлы

```bash
# Основная директория скриптов
mkdir -p ~/.claude/buildserver
cp -r /путь/к/проекту/telegram-bot/* ~/.claude/buildserver/
```

### 2. Создать конфиги токенов

```bash
# Основной бот
mkdir -p ~/.claude/channels/telegram
echo "TELEGRAM_BOT_TOKEN=1234567890:AABBcc..." > ~/.claude/channels/telegram/.env

# Бот Вовка
mkdir -p ~/.claude/channels/telegram-mama
echo "TELEGRAM_BOT_TOKEN=9876543210:ZZYYxx..." > ~/.claude/channels/telegram-mama/.env

# Контрол-бот
echo "TELEGRAM_CONTROL_BOT_TOKEN=1111111111:CCDDee..." > ~/.claude/buildserver/control.env
```

### 3. Настроить allowlist

```bash
# Узнать свой chat_id: написать боту /start, потом проверить логи
# или использовать @userinfobot
cat > ~/.claude/channels/telegram/access.json << 'EOF'
{
  "allowFrom": ["ВАШ_CHAT_ID"]
}
EOF
```

### 4. Подключить плагин

```bash
# Войти в Claude Code и активировать плагин
claude
# Внутри:
/login
# Добавить канал telegram в настройках плагина
```

### 5. Установить хуки в settings.json

Добавить в `~/.claude/settings.json` раздел `hooks` — см. [installation.md](./installation.md#hooks).

### 6. Установить LaunchD и запустить

```bash
bash ~/.claude/buildserver/install-launchd.sh
bash ~/.claude/buildserver/claude-bot.sh start
bash ~/.claude/buildserver/register-bot-commands.sh
```

### 7. Проверить

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

Напишите в Telegram основному боту — он ответит. Готово.

---

## Структура файлов

```
~/.claude/buildserver/
├── claude-bot.sh              # Управление сессиями (start/stop/restart/status)
├── commands.ts                # Контрол-бот (Bun)
├── tglib.ts                   # Общие Telegram-хелперы
├── launchd-boot.sh            # Watchdog (запускается launchd)
├── install-launchd.sh         # Установка launchd-агента
├── new-session.sh             # Создание новой сессии
├── register-bot-commands.sh   # Регистрация команд в меню Telegram
│
├── on-stop.ts                 # Оркестратор Stop-хука
├── notify-stop.ts             # Уведомление о завершении хода
├── compact-check.ts           # Автоматический compact/clear
├── prompt-submitted.ts        # UserPromptSubmit хук (🤔 Думаю…)
├── progress.ts                # PostToolUse хук (прогресс)
├── notify-stuck.ts            # Алерт о зависании
│
├── transcribe.sh              # STT (ElevenLabs/OpenAI/Mistral)
├── tts.sh                     # TTS (ElevenLabs Flash)
├── VOICE-INSTRUCTIONS.md      # Инструкции по голосу для Claude
│
├── com.alexlevnikov.claude-buildserver.plist  # LaunchD plist
├── control.env                # Токен контрол-бота
├── transcribe.env             # Ключи STT/TTS
│
└── state/
    ├── prompt-active.json     # Активный промпт (для stuck-детектора)
    ├── prompt-active.alerted  # Флаг: алерт уже отправлен
    ├── last-stop.txt          # Время последнего Stop-хука
    └── tts-usage.json         # Расход TTS по дням

~/.claude/channels/telegram/
├── .env                       # TELEGRAM_BOT_TOKEN основного бота
└── access.json                # { "allowFrom": ["chat_id", ...] }

~/.claude/channels/telegram-mama/
├── .env                       # TELEGRAM_BOT_TOKEN бота Вовка
└── access.json                # Отдельный allowlist

~/Documents/Projects/CLAUDE.md  # Инструкции для основного бота
~/Documents/MamaBot/CLAUDE.md   # Инструкции для Вовки
```
