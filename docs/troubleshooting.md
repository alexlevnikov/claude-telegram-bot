# Устранение неполадок

---

## Бот не отвечает

### Чеклист диагностики

Выполните по порядку:

```bash
# 1. Жива ли screen-сессия?
screen -ls
```

Если нет строки с `.claude (Detached)` или `.claude (Attached)`:

```bash
# Перезапустить вручную
bash ~/.claude/buildserver/claude-bot.sh start
```

```bash
# 2. Есть ли LaunchD агент?
launchctl list | grep claude-buildserver
```

Если пусто — агент не загружен:

```bash
bash ~/.claude/buildserver/install-launchd.sh
```

```bash
# 3. Что происходит в сессии?
screen -S claude -X hardcopy /tmp/check.txt && cat /tmp/check.txt
```

Возможные варианты:
- Ожидание ввода `>` — всё нормально, Claude ждёт задачу
- `PermissionRequest` — Claude ждёт разрешения, ответьте в терминале или нажмите 🛑 Стоп в Telegram
- Ошибка подключения к API — проблема с сетью или кредитами
- Сессия завершилась — нет вывода

```bash
# 4. Доступен ли Telegram-плагин?
cat ~/.claude/channels/telegram/.env
cat ~/.claude/channels/telegram/access.json
```

Убедитесь что токен правильный и ваш chat_id в `allowFrom`.

```bash
# 5. Токен рабочий?
TOKEN=$(grep TELEGRAM_BOT_TOKEN ~/.claude/channels/telegram/.env | cut -d= -f2)
curl -s "https://api.telegram.org/bot${TOKEN}/getMe" | python3 -m json.tool
```

Должно вернуть `"ok": true` и данные бота.

---

## Сессия завела — Claude завис

### Симптомы

- Отправили задачу, 🤔 Думаю… появилось, но прошло 15+ минут и ответа нет
- Пришёл алерт от контрол-бота: `⚠️ Claude не отвечает N мин`

### Диагностика

```bash
# Смотрим что происходит в screen
screen -r claude
# (Ctrl+A D для выхода из screen без закрытия)
```

### Решения по ситуации

**Ожидает PermissionRequest:**

Выглядит примерно так в терминале:
```
⚠ Tool use requires permission: Bash(rm -rf ...)
Allow? (y/n)
```

Варианты:
1. Подключиться `screen -r claude` и ответить `y` или `n`
2. Нажать 🔄 Перезапустить в алерте контрол-бота (это отправит `/restart`)
3. Добавить разрешение в `settings.json` чтобы не спрашивало в будущем

**Долгая операция (сборка, тесты):**

```bash
# Проверить что Claude реально работает
ps aux | grep claude | grep -v grep
```

Если процесс есть — просто ждать. Для длинных задач увеличьте порог:

```bash
STUCK_MINUTES=30 bash ~/.claude/buildserver/launchd-boot.sh
```

**Claude завис без причины:**

1. Нажать 🛑 Прервать (Esc) в контрол-боте
2. Подождать 30 секунд
3. Написать новый запрос или нажать 🔄

---

## Мёртвые screen-сокеты

### Симптом

```
screen -ls
```

Показывает:
```
There are screens on:
    12345.claude (??:??)	(Dead ???)
```

Или при попытке подключения:
```
There is no screen to be resumed matching claude.
```

### Решение

```bash
# Очистить мёртвые сокеты
screen -wipe

# Проверить снова
screen -ls

# Запустить заново
bash ~/.claude/buildserver/claude-bot.sh start
```

Если `screen -wipe` не помогает:

```bash
# Найти и удалить вручную
ls /tmp/screens/
rm -rf /tmp/screens/S-$USER/*/
screen -wipe
```

---

## Контрол-бот не отвечает

### Диагностика

```bash
# Жив ли процесс?
cat ~/.claude/buildserver/commands.pid | xargs -I{} ps -p {}

# Или через pgrep
pgrep -f "buildserver/commands.ts"

# Лог
tail -50 ~/.claude/buildserver/commands.log
```

### Частые причины и решения

**Токен не валиден:**

```
commands: токен не принят
```

Проверить токен:
```bash
TOKEN=$(grep TELEGRAM_CONTROL_BOT_TOKEN ~/.claude/buildserver/control.env | cut -d= -f2)
curl -s "https://api.telegram.org/bot${TOKEN}/getMe"
```

**Allowlist пуст:**

```
commands: allowlist пуст
```

Проверить:
```bash
cat ~/.claude/channels/telegram/access.json
```

Должно быть: `{"allowFrom": ["ваш_chat_id"]}`

**Процесс упал:**

```bash
# Запустить вручную
nohup bun ~/.claude/buildserver/commands.ts >> ~/.claude/buildserver/commands.log 2>&1 &
echo $! > ~/.claude/buildserver/commands.pid
```

LaunchD поднимет его сам в течение минуты — можно просто подождать.

---

## Кредиты исчерпаны

### Что работает, что нет

| Компонент | Статус |
|---|---|
| Контрол-бот | ✅ |
| `/status` в контрол-боте | ✅ |
| `/restart` в контрол-боте | ✅ |
| Алерты stuck-детектора | ✅ |
| LaunchD watchdog | ✅ |
| Основной бот (ответы) | ❌ |
| Бот Вовка (ответы) | ❌ |
| Хуки (notify-stop, progress) | ❌ |

### Сообщение об ошибке

В screen-сессии:
```
Claude Code error: Credit balance too low
```

Или в Telegram ничего не приходит после отправки сообщения.

### Действия

1. Пополнить баланс на [console.anthropic.com](https://console.anthropic.com)
2. Перезапустить сессию через контрол-бот: `/restart`
3. Или подождать — launchd через минуту сам перезапустит

---

## Плагин не загружается

### Симптомы

- Бот не отвечает на Telegram-сообщения
- В screen нет упоминания `plugin:telegram`
- Или: `plugin not found: telegram`

### Диагностика

```bash
# Подключиться к сессии
screen -r claude

# Внутри проверить какие каналы подключены
# Claude Code должен показать "Telegram" в списке каналов
```

### Решения

**Плагин не установлен:**

```bash
# Выйти из screen (Ctrl+A D) и запустить Claude Code вручную
claude --channels "plugin:telegram@claude-plugins-official"
# Если предложит установить плагин — согласиться
```

**Неправильный путь к .env:**

```bash
# Проверить что файл существует
ls -la ~/.claude/channels/telegram/.env
cat ~/.claude/channels/telegram/.env
```

Токен должен быть в формате `TELEGRAM_BOT_TOKEN=число:строка`

**Плагин был обновлён и сломался:**

```bash
# Попробовать без --channels для диагностики
cd ~/Documents/Projects
BUILD_SERVER=1 claude
# Внутри вручную подключить: /channels add telegram
```

**access.json повреждён:**

```bash
# Проверить валидность JSON
python3 -m json.tool ~/.claude/channels/telegram/access.json
```

Должно быть `{"allowFrom": ["числа_строкой"]}` — без синтаксических ошибок.

---

## Команды не показываются в меню Telegram

### Симптом

При нажатии `/` в Telegram не появляется список команд, или появляется пустой список.

### Решение

```bash
# Перерегистрировать команды
bash ~/.claude/buildserver/register-bot-commands.sh

# Только для основного бота
bash ~/.claude/buildserver/register-bot-commands.sh main

# Только для Вовки
bash ~/.claude/buildserver/register-bot-commands.sh mama
```

**Почему команды сбрасываются:** плагин при каждом запуске вызывает `setMyCommands` со своим набором (по умолчанию пустым или минимальным). Скрипт `new-session.sh` автоматически перерегистрирует команды после поднятия сессии.

### Проверка токена

```bash
TOKEN=$(grep TELEGRAM_BOT_TOKEN ~/.claude/channels/telegram/.env | cut -d= -f2)
curl -s "https://api.telegram.org/bot${TOKEN}/getMyCommands" | python3 -m json.tool
```

---

## Хуки не работают

### Симптомы

- Нет сообщения «🤔 Думаю…» при отправке задачи
- Нет уведомлений ✅/❌ после ответа
- Нет прогресса при работе с инструментами

### Диагностика

```bash
# Проверить что хуки настроены
cat ~/.claude/settings.json | python3 -m json.tool | grep -A 20 '"hooks"'
```

```bash
# Проверить что BUILD_SERVER=1 установлен в env сессии
screen -S claude -X hardcopy /tmp/env_check.txt
grep BUILD_SERVER /tmp/env_check.txt
```

```bash
# Тест хука вручную
echo '{"cwd":"/tmp","transcript_path":""}' | BUILD_SERVER=1 bun ~/.claude/buildserver/prompt-submitted.ts
echo $?
```

### Частые причины

**`BUILD_SERVER` не установлен:**

Хуки проверяют `process.env.BUILD_SERVER !== "1"` и молча выходят. Убедитесь что `claude-bot.sh` экспортирует переменную:

```bash
# В claude-bot.sh должно быть:
export BUILD_SERVER=1
```

**bun не найден:**

```bash
which bun
# Должно вернуть /Users/you/.bun/bin/bun

# Если не найден:
curl -fsSL https://bun.sh/install | bash
# Перезапустить терминал
```

**Путь к скриптам неправильный:**

Хуки в `settings.json` должны использовать абсолютный путь:

```json
"command": "bun /Users/alexlevnikov/.claude/buildserver/prompt-submitted.ts"
```

Или с `~` если shell раскрывает его:

```json
"command": "bun ~/.claude/buildserver/prompt-submitted.ts"
```

---

## Бот Вовка не отвечает Светлане

### Проверить screen-сессию

```bash
screen -ls | grep claude-mama
screen -r claude-mama
```

### Проверить токен

```bash
TOKEN=$(grep TELEGRAM_BOT_TOKEN ~/.claude/channels/telegram-mama/.env | cut -d= -f2)
curl -s "https://api.telegram.org/bot${TOKEN}/getMe"
```

### Проверить allowlist

```bash
cat ~/.claude/channels/telegram-mama/access.json
```

Должен содержать chat_id Светланы.

### Перезапустить

```bash
bash ~/.claude/buildserver/claude-bot.sh restart-mama
```

Или через контрол-бот: `/restart_mama`

---

## Голосовые сообщения не работают

### Транскрипция не работает

```bash
# Тест с тестовым аудиофайлом
bash ~/.claude/buildserver/transcribe.sh /tmp/test.ogg
echo "exit code: $?"
```

```bash
# Проверить конфиг
cat ~/.claude/buildserver/transcribe.env

# Проверить переменные
ENVF=~/.claude/buildserver/transcribe.env
set -a && . "$ENVF" && set +a
echo "Провайдер: $TRANSCRIBE_PROVIDER"
echo "Ключ: ${OPENAI_API_KEY:0:10}..."
```

### TTS не работает

```bash
# Тест
bash ~/.claude/buildserver/tts.sh "Привет, это тест"
echo "exit code: $?"
# exit 0 → путь к .ogg файлу
# exit 1 → ошибка API
# exit 2 → фильтр (текст слишком длинный или содержит код)
# exit 3 → дневной лимит исчерпан
```

```bash
# Проверить дневной расход
cat ~/.claude/buildserver/state/tts-usage.json
```

```bash
# Сбросить лимит вручную (если нужно)
DATE=$(date +%Y-%m-%d)
python3 -c "
import json
with open('/Users/$USER/.claude/buildserver/state/tts-usage.json', 'r+') as f:
    d = json.load(f)
    d['$DATE'] = 0
    f.seek(0); json.dump(d, f); f.truncate()
print('Лимит сброшен')
"
```

---

## Ядерный сброс — полная переустановка

Если ничего не помогает и нужно начать с нуля:

### Шаг 1: Остановить всё

```bash
# Остановить боты
bash ~/.claude/buildserver/claude-bot.sh stop

# Убить контрол-бот
pkill -f "buildserver/commands.ts" 2>/dev/null || true

# Выгрузить launchd
launchctl unload ~/Library/LaunchAgents/com.alexlevnikov.claude-buildserver.plist 2>/dev/null || true

# Удалить мёртвые screen-сокеты
screen -wipe
```

### Шаг 2: Очистить состояние

```bash
# Удалить временные файлы
rm -f /tmp/claude-tg-progress-*.json
rm -f /tmp/claude-tts-*.ogg

# Очистить состояние хуков
rm -f ~/.claude/buildserver/state/prompt-active.json
rm -f ~/.claude/buildserver/state/prompt-active.alerted
rm -f ~/.claude/buildserver/commands.pid
```

### Шаг 3: Обновить файлы (если нужно)

```bash
# Если обновляете версию скриптов
cp /путь/к/новым/скриптам/* ~/.claude/buildserver/
chmod +x ~/.claude/buildserver/*.sh
```

### Шаг 4: Проверить конфиги

```bash
# Основной токен
cat ~/.claude/channels/telegram/.env

# Контрол-бот токен
cat ~/.claude/buildserver/control.env

# Allowlist
cat ~/.claude/channels/telegram/access.json

# Хуки
python3 -m json.tool ~/.claude/settings.json | grep -A 10 '"hooks"'
```

### Шаг 5: Перезапустить

```bash
# Установить launchd
bash ~/.claude/buildserver/install-launchd.sh

# Запустить боты
bash ~/.claude/buildserver/claude-bot.sh start

# Проверить статус
bash ~/.claude/buildserver/claude-bot.sh status

# Зарегистрировать команды
bash ~/.claude/buildserver/register-bot-commands.sh
```

### Шаг 6: Проверить работу

```bash
# Логи
tail -f ~/.claude/buildserver/commands.log &
tail -f ~/.claude/buildserver/launchd.err.log &

# Написать в Telegram и убедиться что бот отвечает
```

---

## Таблица кодов выхода хуков

| Скрипт | Exit code | Значение |
|---|---|---|
| `prompt-submitted.ts` | 0 | Успех |
| `progress.ts` | 0 | Успех |
| `on-stop.ts` | 0 | Успех |
| `notify-stop.ts` | 0 | Успех |
| `compact-check.ts` | 0 | Успех или не нужен compact |
| `tts.sh` | 0 | Успех, stdout = путь к .ogg |
| `tts.sh` | 1 | Ошибка API ElevenLabs |
| `tts.sh` | 2 | Фильтр: текст > 500 символов или содержит код |
| `tts.sh` | 3 | Дневной лимит символов исчерпан |
| `transcribe.sh` | 0 | Успех, stdout = текст |
| `transcribe.sh` | 1 | Ошибка (файл не найден, API недоступен) |

---

## Диагностические команды одним блоком

```bash
#!/usr/bin/env bash
# Запуск: bash ~/.claude/buildserver/diagnose.sh
echo "=== Screen-сессии ==="
screen -ls

echo ""
echo "=== LaunchD агент ==="
launchctl list | grep claude-buildserver || echo "НЕ ЗАГРУЖЕН"

echo ""
echo "=== Контрол-бот ==="
PID_FILE=~/.claude/buildserver/commands.pid
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    ps -p "$PID" -o pid,command 2>/dev/null || echo "Процесс $PID не найден"
else
    echo "PID-файл не существует"
fi

echo ""
echo "=== Stuck-флаг ==="
STATE=~/.claude/buildserver/state/prompt-active.json
if [ -f "$STATE" ]; then
    AGE=$(( ( $(date +%s) - $(stat -f %m "$STATE") ) / 60 ))
    echo "Файл существует, возраст: ${AGE} мин"
    cat "$STATE"
else
    echo "Нет активного промпта"
fi

echo ""
echo "=== Последний ответ ==="
cat ~/.claude/buildserver/state/last-stop.txt 2>/dev/null || echo "Нет данных"

echo ""
echo "=== Последние логи watchdog ==="
tail -10 ~/.claude/buildserver/launchd.err.log

echo ""
echo "=== Последние логи контрол-бота ==="
tail -10 ~/.claude/buildserver/commands.log
```
