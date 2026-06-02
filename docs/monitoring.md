# Мониторинг и авто-восстановление

---

## Обзор системы мониторинга

Система построена на трёх уровнях:

```
Уровень 1: launchd (каждые 60 сек)
    ├── Watchdog screen-сессий → авто-recovery
    ├── Watchdog контрол-бота → авто-restart
    └── Stuck-детектор → алерт в Telegram

Уровень 2: контрол-бот (always-on)
    ├── Получает алерты от хуков
    ├── Обрабатывает кнопки ▶/🔁/🛑/🔄
    └── Отвечает на /status, /restart

Уровень 3: хуки Claude Code (event-driven)
    ├── UserPromptSubmit → записывает "Claude занят"
    ├── PostToolUse → live-прогресс
    └── Stop → "Claude освободился" + compact-check
```

---

## LaunchD Watchdog

### Как работает

LaunchD запускает `launchd-boot.sh` каждые 60 секунд и при каждом логине.

```xml
<key>RunAtLoad</key>
<true/>
<key>StartInterval</key>
<integer>60</integer>
```

Скрипт идемпотентный: запускается каждую минуту, но делает что-то только если есть проблема.

### Логика watchdog

```bash
# 1. Stuck-детектор (всегда первым)
check_stuck

# 2. Контрол-бот
ensure_commands_bot

# 3. Авто-recovery сессии
if screen -ls | grep "\.claude"; then
    exit 0   # всё хорошо, уходим
fi
# Сессия мертва — поднимаем
```

### Авто-recovery screen-сессии

При обнаружении мёртвой screen-сессии:

1. Логирует событие в `launchd.err.log`
2. Отправляет уведомление в Telegram через контрол-бот: `🔄 Билд-сервер перезапустился`
3. Создаёт новую screen-сессию с правильными переменными окружения

```bash
screen -dmS "$SESSION" bash -c "
  export BUILD_SERVER=1 TMUX_SESSION='$SESSION' BUILD_DIR='$BUILD_DIR'
  export COMPACT_THRESHOLD='35' CLEAR_THRESHOLD='80'
  ...
  exec caffeinate -dimsu claude --remote-control 'Build Server' \
    --channels 'plugin:telegram@claude-plugins-official'
"
```

### Watchdog контрол-бота

Контрол-бот может упасть (OOM, сетевая ошибка, перезапуск системы). LaunchD каждую минуту проверяет его живость:

```bash
ensure_commands_bot() {
    # Проверяем PID-файл
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        kill -0 "$pid" && return 0   # жив
    fi
    # Запасная проверка через pgrep
    if pgrep -f "buildserver/commands.ts" > /dev/null; then
        pgrep -f ... | head -1 > "$pid_file"   # обновляем PID-файл
        return 0
    fi
    # Не найден — запускаем
    nohup bun "$BS/commands.ts" >> "$log_file" 2>&1 &
    echo $! > "$pid_file"
}
```

Контрол-бот запускается в фоне (`nohup ... &`), независимо от screen-сессий и LaunchD.

### Логи watchdog

```bash
# Вывод stdout
tail -f ~/.claude/buildserver/launchd.out.log

# Вывод stderr (события о перезапусках)
tail -f ~/.claude/buildserver/launchd.err.log
```

Пример содержимого `launchd.err.log`:
```
2026-06-02 09:00:01 контрол-бот не найден — поднимаю
2026-06-02 09:01:00 поднимаю билд-сервер в screen 'claude' (cwd=/Users/alex/Documents/Projects)
2026-06-02 14:32:00 контрол-бот не найден — поднимаю
```

---

## Stuck-детектор

### Принцип работы

**«Stuck»** — ситуация когда Claude Code получил задачу, но не отвечает дольше ожидаемого. Причины:

- Ожидает разрешения (PermissionRequest) которое некому дать
- Завис на долгой операции (сборка, тест)
- Зациклился в инструментах
- Системная проблема (сеть, ресурсы)

**Механизм:**

```
UserPromptSubmit     Stop-хук
     │                   │
     ▼                   ▼
prompt-active.json  удаляется
создаётся

     │
     ▼ (каждую минуту проверяет launchd)
age = (now - mtime(prompt-active.json)) / 60
age >= STUCK_MINUTES (15) → алерт
```

Файл `prompt-active.json` создаётся при каждом промпте и удаляется когда Claude отвечает. Если файл существует и старый — Claude явно занят слишком долго.

### Содержание файла

```json
{
  "submittedAt": "2026-06-02T14:30:00.000Z",
  "cwd": "/Users/alexlevnikov/Documents/Projects/my-app",
  "transcript_path": "/Users/alexlevnikov/.claude/projects/.../transcript.jsonl"
}
```

Из `cwd` watchdog извлекает имя проекта (`basename`) для алерта.

### Алерт о зависании

```
⚠️ Claude не отвечает 22 мин — my-app

Возможно, ждёт разрешения или завис.
```

Кнопки:

| Кнопка | Callback | Действие |
|---|---|---|
| 🛑 Прервать (Esc) | `bs:stop` | `screen -S claude -X stuff "\x1b"` — Escape |
| 🔄 Перезапустить | `bs:restart` | Esc + `/restart` в screen |

### Флаг `.alerted`

После отправки алерта watchdog создаёт `prompt-active.alerted`. При следующей проверке через 60 секунд, если Claude всё ещё занят — алерт **не** отправляется повторно (файл уже есть).

Флаг удаляется в `notify-stop.ts` вместе с `prompt-active.json`, когда Claude наконец отвечает. Это позволяет корректно алертить следующие зависания.

### Настройка чувствительности

```bash
# В launchd plist или при запуске
STUCK_MINUTES=15    # по умолчанию

# Более агрессивно
STUCK_MINUTES=10

# Для долгих задач (сборка, тесты)
STUCK_MINUTES=30
```

---

## Уведомления контрол-бота

### Карта всех уведомлений

| Событие | Иконка | Откуда | Кнопки |
|---|---|---|---|
| Claude завершил ход (без Telegram-ответа) | ✅/❌ | `notify-stop.ts` | ▶ 🔁 🛑 |
| Claude завис | ⚠️ | `notify-stuck.ts` (через launchd) | 🛑 🔄 |
| Сессия перезапустилась автоматически | 🔄 | `launchd-boot.sh` | — |
| Сессия ушла в оффлайн для перезапуска | 🔴 | `new-session.sh` | — |
| Сессия вернулась онлайн | 🟢 | `new-session.sh` | — |

### Уведомление ✅/❌ (Stop-хук)

Формируется в `notify-stop.ts`. Логика:

1. Читает последний ход ассистента из транскрипта (последние 600 строк)
2. Сбрасывает счётчики при каждом `user`-сообщении (нас интересует только последний ход)
3. Собирает тексты (`text` блоки) и инструменты (`tool_use` блоки)
4. Проверяет `tool_result` на паттерны ошибок: `Error:`, `FAILED`, `exit code N`, `permission denied` и т.д.
5. Если среди инструментов был `reply` (Claude уже ответил в Telegram) — **не отправляет** дублирующее уведомление
6. Иначе формирует уведомление с первыми 500 символами последнего текстового ответа

```
✅ Готово — my-app

Рефакторинг завершён. Разбил AuthService на три модуля:
TokenValidator, SessionManager, PermissionChecker. Все тесты
проходят (47/47). Коммит сделан.
```

### Кнопки Stop-хука

Обрабатываются в `commands.ts`:

**▶ Продолжить (`bs:continue`)**

Если сессия жива — инжектирует пустую строку (Enter) в screen. Claude воспринимает это как «продолжай».

```typescript
screenInject(SESSION, "");  // screen -S claude -X stuff "\r"
```

**🔁 Повторить (`bs:retry`)**

Инжектирует «Попробуй снова»:

```typescript
screenInject(SESSION, "Попробуй снова");
```

**🛑 Стоп (`bs:stop`)**

Отправляет Escape:

```typescript
screenEsc();  // screen -S claude -X stuff "\x1b"
```

---

## Offline/Online уведомления

При `/newsession` запускается `new-session.sh`, который:

```bash
# Сразу возвращает управление Claude (не блокирует)
echo "scheduled:main:delay=4s"
exit 0

# Фоновый процесс (независим от screen-сессии):
sleep 4
notify "🔴 Билд-сервер: перезапуск — ухожу в оффлайн на ~15 сек"
claude-bot.sh restart-main

# Ждём поднятия сессии (до 60 сек)
for i in 1..20; do
    sleep 3
    screen -ls | grep "\.claude" && {
        sleep 10  # ждём подключения Telegram-плагина
        register-bot-commands.sh main
        notify "🟢 Билд-сервер: снова онлайн"
        exit 0
    }
done

notify "⚠️ Билд-сервер: сессия не поднялась за 60 сек — проверь вручную"
```

**Почему задержка 4 секунды:** Claude должен успеть отправить ответ «Создаю новую сессию...» перед тем как сессия убьётся. 4 секунды — достаточно для reply-инструмента.

**Почему 10 секунд ожидания после поднятия:** Telegram-плагин нужно время на подключение к Bot API. Если зарегистрировать команды сразу — они могут сброситься плагином при инициализации.

---

## Выживание при исчерпании кредитов

При исчерпании кредитов Anthropic:

| Компонент | Статус | Причина |
|---|---|---|
| Основной бот | ❌ не отвечает | Требует API Anthropic |
| Бот Вовка | ❌ не отвечает | Требует API Anthropic |
| Контрол-бот | ✅ работает | Только Telegram API |
| LaunchD watchdog | ✅ работает | Bash + screen |
| `/status` в контрол-боте | ✅ | `screen -ls` |
| `/restart` в контрол-боте | ✅ | `claude-bot.sh restart-main` |
| Алерты о зависании | ✅ | Через контрол-бот |

**Практический сценарий:** Claude завис пока кредиты ещё были. Кредиты закончились. Watchdog через 15 минут отправит алерт через контрол-бот — вы нажмёте 🔄 Перезапустить. Сессия перезапустится. Как только пополните кредиты — бот продолжит работать.

---

## Проверка состояния системы

### Полный чеклист здоровья

```bash
# 1. Screen-сессии
screen -ls

# 2. LaunchD агент
launchctl list | grep claude-buildserver

# 3. Контрол-бот (PID)
cat ~/.claude/buildserver/commands.pid | xargs -I{} ps -p {}

# 4. Stuck-флаг (если есть — Claude занят или завис)
ls -la ~/.claude/buildserver/state/prompt-active.json 2>/dev/null && \
  echo "Claude занят с $(stat -f %Sm -t '%H:%M:%S' ~/.claude/buildserver/state/prompt-active.json)"

# 5. Логи watchdog
tail -20 ~/.claude/buildserver/launchd.err.log

# 6. Логи контрол-бота
tail -20 ~/.claude/buildserver/commands.log
```

### Через Telegram

Написать контрол-боту `/status`:

```
🟢 claude
🟢 claude-mama
```

### Через основного бота

Написать `/status`:

```
📊 Статус

Сессии:
  12345.claude (Detached)
  12346.claude-mama (Detached)

Модель: claude-opus-4-5
Последний ответ: 02.06.2026, 15:41:22
```
