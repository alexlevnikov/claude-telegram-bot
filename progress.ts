#!/usr/bin/env bun
// PostToolUse hook: live-обновления прогресса в Telegram через edit_message.
// Только при BUILD_SERVER=1 и только если задача пришла из Telegram-канала.
//
// Ключ состояния: chatId_threadId (для суперогрупп-форумов) или просто chatId (для DM).
// Это предотвращает коллизию прогресс-сообщений между разными топиками одной группы.
import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { api, loadToken } from "./tglib.ts";

const LABELS: Record<string, string> = {
  Read:      "📖 читает файл",
  Write:     "✏️  пишет файл",
  Edit:      "✏️  редактирует файл",
  Bash:      "⚙️  выполняет команду",
  WebFetch:  "🌐 загружает страницу",
  WebSearch: "🔍 ищет в интернете",
  TodoWrite: "📋 обновляет задачи",
  Task:      "🤖 запускает агента",
};

// ─── state файл ────────────────────────────────────────────────────────────
// Ключ = chatId + опционально _threadId чтобы не перепутать топики одной группы
function stateKey(chatId: string, threadId?: string) {
  return threadId ? `${chatId}_${threadId}` : chatId;
}
function stateFile(key: string) {
  return `/tmp/claude-tg-progress-${key}.json`;
}
function readState(key: string): { msgId: number } | null {
  try { return JSON.parse(readFileSync(stateFile(key), "utf8")); } catch { return null; }
}
function writeState(key: string, msgId: number, info: { chatId: string; threadId?: string }) {
  // chatId/threadId сохраняем, чтобы notify-stop мог удалить это сообщение по завершении.
  writeFileSync(stateFile(key), JSON.stringify({ msgId, chatId: info.chatId, threadId: info.threadId }));
}

// ─── извлечение chat_id + message_thread_id из транскрипта ─────────────────
type TgInfo = { chatId: string; threadId?: string } | null;

function lastTelegramInfo(transcriptPath: string): TgInfo {
  try {
    const lines = readFileSync(transcriptPath, "utf8").split("\n").slice(-300);
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].trim()) continue;
      try {
        const ev      = JSON.parse(lines[i]);
        const content = ev.message?.content ?? ev.content;

        // Путь 1: ищем в массиве блоков (tool_result или text с channel-тегом)
        if (Array.isArray(content)) {
          for (const b of content) {
            const text = b?.type === "tool_result"
              ? (typeof b.content === "string" ? b.content : b.content?.[0]?.text ?? "")
              : b?.type === "text" ? (b.text ?? "") : "";
            const chatMatch   = text.match(/chat_id="(\d+)"/);
            if (!chatMatch) continue;
            const threadMatch = text.match(/message_thread_id="(\d+)"/);
            return { chatId: chatMatch[1], threadId: threadMatch?.[1] };
          }
        }
        // Путь 2: строковый контент
        if (typeof content === "string") {
          const chatMatch = content.match(/chat_id="(\d+)"/);
          if (chatMatch) {
            const threadMatch = content.match(/message_thread_id="(\d+)"/);
            return { chatId: chatMatch[1], threadId: threadMatch?.[1] };
          }
        }
      } catch {}
    }
  } catch {}
  return null;
}

// ─── main ──────────────────────────────────────────────────────────────────
async function main() {
  if (process.env.BUILD_SERVER !== "1") return;
  const token = loadToken();
  if (!token) return;

  let payload: any = {};
  try { payload = JSON.parse(await Bun.stdin.text()); } catch {}

  const toolName: string   = payload.tool_name  ?? "";
  // Не отправляем прогресс о собственных инструментах Telegram-канала —
  // это рекурсивный шум (само сообщение и так приходит в чат).
  if (toolName.startsWith("mcp__plugin_telegram_telegram__")) return;
  const toolInput: any     = payload.tool_input ?? {};
  const transcript: string | undefined = payload.transcript_path;
  if (!transcript) return;

  const info = lastTelegramInfo(transcript);
  if (!info) return; // задача не из Telegram — молчим

  const key   = stateKey(info.chatId, info.threadId);
  const label = LABELS[toolName] ?? `⚙️  ${toolName}`;
  let detail  = "";
  if (toolInput.file_path) detail = ` \`${toolInput.file_path.split("/").slice(-2).join("/")}\``;
  else if (toolInput.command) detail = ` \`${String(toolInput.command).slice(0, 60)}\``;
  else if (toolInput.query)   detail = ` "${String(toolInput.query).slice(0, 60)}"`;
  const progressText = `${label}${detail}…`;

  const state = readState(key);
  const msgParams: Record<string, any> = { chat_id: info.chatId };
  if (info.threadId) msgParams.message_thread_id = Number(info.threadId);

  try {
    if (state) {
      await api(token, "editMessageText", {
        ...msgParams,
        message_id: state.msgId,
        text: progressText,
      });
    } else {
      const sent: any = await api(token, "sendMessage", { ...msgParams, text: progressText });
      if (sent?.ok) writeState(key, sent.result.message_id, info);
    }
  } catch {}
}

main().catch(() => {});
