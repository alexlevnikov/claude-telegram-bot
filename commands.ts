#!/usr/bin/env bun
// Контрол-бот — только мониторинг и алерты.
//
// Зона ответственности:
//   • callback_query от Stop-хука (▶ Продолжить / 🔁 Повторить / 🛑 Стоп)
//   • callback_query от stuck-алертов (🛑 Прервать / 🔄 Перезапустить)
//   • /restart, /restart_mama — поднять мёртвую сессию
//   • /status — быстрая проверка без Claude
//
// Всё остальное (меню, проекты, модель, compact, логи) — живёт в самих ботах.

import { homedir } from "node:os";
import { join }    from "node:path";
import { spawnSync } from "node:child_process";
import { loadControlToken, chatIds, api } from "./tglib.ts";

// ─── конфиг ────────────────────────────────────────────────────────────────
const SESSION      = process.env.TMUX_SESSION ?? "claude";
const MAMA_SESSION = "claude-mama";
const BS           = join(homedir(), ".claude", "buildserver");

// ─── screen хелперы ────────────────────────────────────────────────────────
const screenAlive = (s = SESSION) =>
  spawnSync("screen", ["-ls"], { encoding: "utf8" }).stdout.includes(`.${s}`);

const screenEsc = (s = SESSION) =>
  spawnSync("screen", ["-S", s, "-X", "stuff", "\x1b"]);

const screenInject = (s: string, text: string) =>
  spawnSync("screen", ["-S", s, "-X", "stuff", `${text}\r`]);

// ─── перезапуск сессии ──────────────────────────────────────────────────────
function restartSession(target: "main" | "mama"): string {
  const label = target === "mama" ? "Вовка" : "Билд-сервер";
  spawnSync("bash", [join(BS, "claude-bot.sh"), `restart-${target}`]);
  return `🔄 ${label}: перезапуск запущен`;
}

// ─── обработка нажатий кнопок ──────────────────────────────────────────────
async function handleCallback(
  token: string, qid: string, chatId: string, data: string,
) {
  let reply = "";

  switch (data) {
    // ── кнопки Stop-хука (приходят после каждого хода Claude) ──
    case "bs:continue":
      reply = screenAlive()
        ? (screenInject(SESSION, ""), "▶ Продолжаю")
        : "⚠️ Сессия не запущена";
      break;
    case "bs:retry":
      reply = screenAlive()
        ? (screenInject(SESSION, "Попробуй снова"), "🔁 Повторяю")
        : "⚠️ Сессия не запущена";
      break;
    case "bs:stop":
      screenEsc();
      reply = "🛑 Esc отправлен";
      break;

    // ── кнопки stuck-алерта ──
    case "bs:restart":
      screenEsc(SESSION);
      await Bun.sleep(400);
      screenInject(SESSION, "/restart");
      reply = "🔄 /restart отправлен";
      break;

    // ── кнопки ручного перезапуска (когда сессия мертва) ──
    case "bs:do_restart_main": reply = restartSession("main"); break;
    case "bs:do_restart_mama": reply = restartSession("mama"); break;

    case "bs:cancel": reply = "❌ Отменено"; break;
  }

  await api(token, "answerCallbackQuery", {
    callback_query_id: qid,
    text: reply.slice(0, 200),
  }).catch(() => {});

  if (reply) {
    await api(token, "sendMessage", { chat_id: chatId, text: reply }).catch(() => {});
  }
}

// ─── обработка текстовых команд ────────────────────────────────────────────
async function handleMessage(token: string, chatId: string, text: string) {
  const cmd = text.trim().split(/\s+/)[0].toLowerCase();
  let reply = "";

  switch (cmd) {
    case "/restart":
    case "/restart_main":
      reply = restartSession("main");
      break;

    case "/restart_mama":
      reply = restartSession("mama");
      break;

    case "/status": {
      const main = screenAlive(SESSION)      ? `🟢 claude`      : `🔴 claude (мёртв)`;
      const mama = screenAlive(MAMA_SESSION) ? `🟢 claude-mama` : `🔴 claude-mama (мёртв)`;
      reply = `${main}\n${mama}`;
      break;
    }

    case "/help":
      reply = [
        "🔧 *Контрол-бот* (мониторинг)",
        "",
        "/status — живы ли сессии",
        "/restart — перезапустить билд-сервер",
        "/restart\\_mama — перезапустить Вовку",
      ].join("\n");
      break;
  }

  if (reply) {
    await api(token, "sendMessage", {
      chat_id: chatId,
      text: reply,
      parse_mode: "Markdown",
    }).catch(() => {});
  }
}

// ─── main ───────────────────────────────────────────────────────────────────
async function main() {
  const token = loadControlToken();
  if (!token) { console.error("commands: нет TELEGRAM_CONTROL_BOT_TOKEN"); return; }

  const allow = new Set(chatIds());
  if (!allow.size) { console.error("commands: allowlist пуст"); return; }

  const me = await api(token, "getMe", {}, 15000).catch(() => null);
  if (!me?.ok) { console.error("commands: токен не принят"); return; }
  console.error(`commands: @${me.result.username} слушает`);

  await api(token, "setMyCommands", {
    commands: JSON.stringify([
      { command: "status",        description: "📊 Статус сессий" },
      { command: "restart",       description: "🔄 Перезапустить билд-сервер" },
      { command: "restart_mama",  description: "🔄 Перезапустить Вовку" },
    ]),
  }).catch(() => {});

  let offset: number | undefined;
  for (;;) {
    let resp: any;
    try {
      resp = await api(token, "getUpdates", {
        ...(offset !== undefined ? { offset } : {}),
        timeout: 55,
        allowed_updates: JSON.stringify(["message", "callback_query"]),
      }, 70_000);
    } catch { await Bun.sleep(3000); continue; }

    for (const upd of resp?.result ?? []) {
      offset = upd.update_id + 1;
      try {
        if (upd.callback_query) {
          const q = upd.callback_query;
          if (allow.has(String(q.from.id))) {
            await handleCallback(token, q.id, String(q.message?.chat.id ?? q.from.id), q.data ?? "");
          } else {
            await api(token, "answerCallbackQuery", { callback_query_id: q.id }).catch(() => {});
          }
        } else if (upd.message?.text) {
          const m = upd.message;
          if (allow.has(String(m.from?.id))) {
            await handleMessage(token, String(m.chat.id), m.text);
          }
        }
      } catch {}
    }
  }
}

main().catch(console.error);
