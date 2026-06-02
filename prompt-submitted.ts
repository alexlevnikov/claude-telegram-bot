#!/usr/bin/env bun
// UserPromptSubmit hook: фиксирует момент отправки промпта.
// Stop-hook удаляет этот файл. launchd-boot.sh каждую минуту
// проверяет — если файл существует и старше STUCK_MINUTES → алерт в Telegram.
//
// Дополнительно: для задач из Telegram сразу шлёт индикатор «🤔 Думаю…»,
// чтобы пользователь видел, что запрос принят и идёт обработка, а не завис.
// Это сообщение потом обновляет progress.ts (тот же state-файл) и удаляет
// notify-stop.ts по завершении хода.
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { loadToken } from "./tglib.ts";

if (process.env.BUILD_SERVER !== "1") process.exit(0);

const STATE_DIR = join(homedir(), ".claude", "buildserver", "state");
const STATE_FILE = join(STATE_DIR, "prompt-active.json");

let payload: any = {};
try { payload = JSON.parse(await Bun.stdin.text()); } catch {}

mkdirSync(STATE_DIR, { recursive: true });
writeFileSync(STATE_FILE, JSON.stringify({
  submittedAt:     new Date().toISOString(),
  cwd:             payload.cwd ?? process.cwd(),
  transcript_path: payload.transcript_path ?? "",
}));

// ─── индикатор «думаю» в Telegram ───────────────────────────────────────────
type TgInfo = { chatId: string; threadId?: string } | null;

// chat_id / message_thread_id ищем сперва в самом промпте, затем в транскрипте.
function findTgInfo(promptText: string, transcriptPath?: string): TgInfo {
  const fromText = (text: string): TgInfo => {
    const chat = text.match(/chat_id="(-?\d+)"/);
    if (!chat) return null;
    const thread = text.match(/message_thread_id="(\d+)"/);
    return { chatId: chat[1], threadId: thread?.[1] };
  };

  if (promptText) {
    const hit = fromText(promptText);
    if (hit) return hit;
  }
  if (transcriptPath) {
    try {
      const lines = readFileSync(transcriptPath, "utf8").split("\n").slice(-300);
      for (let i = lines.length - 1; i >= 0; i--) {
        if (!lines[i].trim()) continue;
        const hit = fromText(lines[i]);
        if (hit) return hit;
      }
    } catch {}
  }
  return null;
}

function progressFile(key: string) {
  return `/tmp/claude-tg-progress-${key}.json`;
}

async function seedThinking() {
  const token = loadToken();
  if (!token) return;

  const promptText: string = typeof payload.prompt === "string" ? payload.prompt : "";
  const info = findTgInfo(promptText, payload.transcript_path);
  if (!info) return; // задача не из Telegram — молчим

  const params: Record<string, any> = { chat_id: info.chatId, text: "🤔 Думаю…" };
  if (info.threadId) params.message_thread_id = Number(info.threadId);

  // Прямой fetch с коротким таймаутом — это пре-хук, нельзя надолго блокировать ход.
  try {
    const body = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) body.set(k, String(v));
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      body,
      signal: AbortSignal.timeout(3500),
    });
    const json: any = await res.json();
    if (json?.ok) {
      const key = info.threadId ? `${info.chatId}_${info.threadId}` : info.chatId;
      writeFileSync(progressFile(key), JSON.stringify({
        msgId:    json.result.message_id,
        chatId:   info.chatId,
        threadId: info.threadId,
      }));
    }
  } catch {}
}

await seedThinking();
