#!/usr/bin/env bun
// Stop-hook: пинг в Telegram когда Claude закончил ход.
//   ✅ — успешно завершил  |  ❌ — обнаружена ошибка
// Отправляется через CONTROL-бот (чтобы можно было добавить inline-кнопки
// и обработать нажатия в commands.ts без конфликта поллеров).
// Только при BUILD_SERVER=1. Если Claude уже ответил через Telegram — не дублируем.
import { readFileSync, readdirSync, unlinkSync, mkdirSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { homedir } from "node:os";
import { join } from "node:path";
import { loadControlToken, loadToken, chatIds, api } from "./tglib.ts";

const MAX_LINES   = 600;
const SUMMARY_CHARS = 500;
const STATE_FILE  = join(homedir(), ".claude", "buildserver", "state", "prompt-active.json");

const ERROR_PATTERNS = [
  /\bError:/i, /\bFAILED\b/, /exit code [1-9]/, /\bfailed\b/i,
  /\bcannot\b.*\bfind\b/i, /\bno such file\b/i, /\bpermission denied\b/i,
];

function lastTurn(path: string) {
  let lines: string[];
  try { lines = readFileSync(path, "utf8").split("\n"); }
  catch { return { texts: [] as string[], tools: [] as string[], hasError: false }; }

  const texts: string[] = [];
  const tools: string[] = [];
  let hasError = false;

  for (let i = Math.max(0, lines.length - MAX_LINES); i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    let ev: any;
    try { ev = JSON.parse(lines[i]); } catch { continue; }
    const role = ev.type ?? ev.role;
    const msg  = ev.message ?? ev;
    if (role === "user") { texts.length = 0; tools.length = 0; hasError = false; continue; }
    if (role !== "assistant") continue;
    const content = msg.content;
    if (typeof content === "string") { texts.push(content); continue; }
    if (!Array.isArray(content)) continue;
    for (const b of content) {
      if (b?.type === "text" && b.text) texts.push(b.text);
      else if (b?.type === "tool_use" && b.name) tools.push(b.name);
      else if (b?.type === "tool_result") {
        const res = typeof b.content === "string" ? b.content : b.content?.[0]?.text ?? "";
        if (ERROR_PATTERNS.some(p => p.test(res))) hasError = true;
      }
    }
  }
  return { texts, tools, hasError };
}

async function clearProgressState() {
  // Чистим ВСЕ progress-файлы — ключ может быть chatId или chatId_threadId.
  // Заодно удаляем сам индикатор («🤔 Думаю…» / «📖 читает файл…») из чата,
  // чтобы после завершения хода оставался только финальный ответ.
  const mainToken = loadToken();
  try {
    for (const f of readdirSync("/tmp")) {
      if (!f.startsWith("claude-tg-progress-")) continue;
      const path = `/tmp/${f}`;
      if (mainToken) {
        try {
          const st = JSON.parse(readFileSync(path, "utf8"));
          // chatId из state; fallback — из имени файла (claude-tg-progress-<chatId>[_<thread>].json)
          const fromName = f.slice("claude-tg-progress-".length, -".json".length).split("_")[0];
          const chatId = st.chatId ?? fromName;
          if (st.msgId && chatId) {
            await api(mainToken, "deleteMessage", { chat_id: chatId, message_id: st.msgId }, 4000).catch(() => {});
          }
        } catch {}
      }
      try { unlinkSync(path); } catch {}
    }
  } catch {}
}
function clearPromptActive() {
  try { unlinkSync(STATE_FILE); } catch {}
  // Баг 3: очищаем и alerted-флаг, иначе повторные застревания не алертятся
  try { unlinkSync(STATE_FILE.replace(".json", ".alerted")); } catch {}
}
function writeLastStop() {
  try {
    mkdirSync(join(homedir(), ".claude", "buildserver", "state"), { recursive: true });
    writeFileSync(
      join(homedir(), ".claude", "buildserver", "state", "last-stop.txt"),
      new Date().toLocaleString("ru-RU"),
    );
  } catch {}
}

async function main() {
  if (process.env.BUILD_SERVER !== "1") return;

  const token = loadControlToken();
  const ids   = chatIds();
  if (!token || ids.length === 0) return;

  await clearProgressState();
  clearPromptActive(); // Claude ответил — убираем флаг "завис" + сбрасываем alerted
  writeLastStop();     // для !ping

  let payload: any = {};
  try { payload = JSON.parse(await Bun.stdin.text()); } catch {}
  const cwd: string      = payload.cwd ?? process.cwd();
  const transcript: string | undefined = payload.transcript_path;

  const { texts, tools, hasError } = transcript
    ? lastTurn(transcript)
    : { texts: [], tools: [], hasError: false };

  // Уже ответил в Telegram — не дублируем
  if (tools.some(t => t.toLowerCase().includes("telegram"))) return;

  let summary = (texts.at(-1) ?? "").trim().replace(/\n\n/g, "\n");
  if (summary.length > SUMMARY_CHARS) summary = summary.slice(0, SUMMARY_CHARS) + "…";

  const proj  = basename(cwd.replace(/\/+$/, "")) || cwd;
  const icon  = hasError ? "❌" : "✅";
  const label = hasError ? "Ошибка" : "Готово";
  let text    = `${icon} ${label} — ${proj}`;
  if (summary) text += `\n\n${summary}`;

  // Inline-кнопки: обрабатываются в commands.ts через callback_query
  const replyMarkup = {
    inline_keyboard: [[
      { text: "▶ Продолжить", callback_data: "bs:continue" },
      { text: "🔁 Повторить",  callback_data: "bs:retry"    },
      { text: "🛑 Стоп",       callback_data: "bs:stop"     },
    ]],
  };

  for (const cid of ids) {
    try {
      await api(token, "sendMessage", {
        chat_id: cid,
        text,
        reply_markup: JSON.stringify(replyMarkup),
      });
    } catch {}
  }
}

main().catch(() => {});
