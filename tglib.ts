// Общие хелперы для Telegram-надстроек билд-сервера (рантайм — Bun).
// Источники токена/allowlist — те же файлы, что и у официального плагина:
//   ~/.claude/channels/telegram/.env        -> TELEGRAM_BOT_TOKEN
//   ~/.claude/channels/telegram/access.json -> allowFrom: [chat_id, ...]
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const STATE_DIR =
  process.env.TELEGRAM_STATE_DIR ??
  join(homedir(), ".claude", "channels", "telegram");
const ENV_FILE  = join(STATE_DIR, ".env");
const ACCESS_FILE = join(STATE_DIR, "access.json");
const CONTROL_ENV = join(homedir(), ".claude", "buildserver", "control.env");

export function loadToken(): string | null {
  if (process.env.TELEGRAM_BOT_TOKEN) return process.env.TELEGRAM_BOT_TOKEN.trim();
  try {
    for (const line of readFileSync(ENV_FILE, "utf8").split("\n")) {
      const m = line.match(/^TELEGRAM_BOT_TOKEN=(.*)$/);
      if (m) return m[1].trim();
    }
  } catch {}
  return null;
}

export function loadControlToken(): string | null {
  if (process.env.TELEGRAM_CONTROL_BOT_TOKEN)
    return process.env.TELEGRAM_CONTROL_BOT_TOKEN.trim();
  try {
    for (const line of readFileSync(CONTROL_ENV, "utf8").split("\n")) {
      const m = line.match(/^TELEGRAM_CONTROL_BOT_TOKEN=(.*)$/);
      if (m) return m[1].trim();
    }
  } catch {}
  return null;
}

export function readAccess(): any {
  try { return JSON.parse(readFileSync(ACCESS_FILE, "utf8")); }
  catch { return {}; }
}

export function chatIds(): string[] {
  return readAccess().allowFrom ?? [];
}

export async function api(
  token: string,
  method: string,
  params: Record<string, any> = {},
  timeoutMs = 70000,
): Promise<any> {
  const body = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (typeof v === "object") body.set(k, JSON.stringify(v));
    else body.set(k, String(v));
  }
  const url = `https://api.telegram.org/bot${token}/${method}`;
  // Один retry при сетевой ошибке (не при 4xx от Telegram)
  for (let attempt = 0; attempt <= 1; attempt++) {
    try {
      const res = await fetch(url, {
        method: "POST",
        body,
        signal: AbortSignal.timeout(timeoutMs),
      });
      return res.json();
    } catch (e) {
      if (attempt === 1) throw e;
      await Bun.sleep(1500);
    }
  }
}

export async function send(
  text: string,
  opts: { token?: string; chatId?: string; replyMarkup?: any } = {},
): Promise<number> {
  const token = opts.token ?? loadToken();
  if (!token) return 0;
  const targets = opts.chatId ? [opts.chatId] : chatIds();
  let ok = 0;
  for (const cid of targets) {
    try {
      const params: Record<string, any> = { chat_id: cid, text };
      if (opts.replyMarkup) params.reply_markup = JSON.stringify(opts.replyMarkup);
      await api(token, "sendMessage", params);
      ok++;
    } catch {}
  }
  return ok;
}
