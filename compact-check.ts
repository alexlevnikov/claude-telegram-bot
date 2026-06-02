#!/usr/bin/env bun
// Stop-hook: управление контекстом сессии.
//
// Двухуровневая стратегия:
//   ≥ COMPACT_THRESHOLD (35%) → /compact  (сжать, сохранить суть разговора)
//   ≥ CLEAR_THRESHOLD   (80%) → /clear    (полный сброс — compact опоздал)
//
// Почему два уровня:
//   compact срабатывает на Stop-хук, но длинные задачи долго не останавливают
//   сессию. К моменту Stop контекст уже 150–200%. /clear спасает в таких случаях.
//   Данные за 01.06: сессия дошла до 203% из-за порога 75% и долгих задач.
//
// Почему cache_read НЕ используется для расчёта процента:
//   Многоуровневый кэш Claude может давать cache_read > размера окна (150–200%),
//   что ложно триггерит clear. Правильная метрика — input + cache_creation,
//   т.е. только "свежие" токены, добавленные в этом и предыдущих ходах.

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { loadControlToken, chatIds, api } from "./tglib.ts";

const COMPACT_THRESHOLD = parseInt(process.env.COMPACT_THRESHOLD ?? "35", 10);
const CLEAR_THRESHOLD   = parseInt(process.env.CLEAR_THRESHOLD   ?? "80", 10);
const SESSION           = process.env.TMUX_SESSION ?? "claude";

// ── Чтение контекста из транскрипта ────────────────────────────────────────

interface ContextInfo {
  pct:        number;   // % заполненности окна
  windowSize: number;
  usedTokens: number;
}

function getContextInfo(transcriptPath: string): ContextInfo | null {
  try {
    const lines = readFileSync(transcriptPath, "utf8").split("\n").slice(-200);
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].trim()) continue;
      try {
        const ev    = JSON.parse(lines[i]);
        const usage = ev.message?.usage ?? ev.usage;
        if (!usage) continue;

        // Используем только "свежие" токены (input + cache_creation).
        // cache_read исключаем — он может превышать размер окна из-за
        // многоуровневого кэша и давать ложные 150–200%.
        const input    = usage.input_tokens                ?? 0;
        const creating = usage.cache_creation_input_tokens ?? 0;
        const fresh    = input + creating;
        if (!fresh) continue;

        // Размер окна: сначала из транскрипта, потом fallback 200K
        const windowSize: number =
          usage.context_window_tokens ?? usage.context_window ?? 200_000;

        return {
          pct: Math.round((fresh / windowSize) * 100),
          windowSize,
          usedTokens: fresh,
        };
      } catch {}
    }
  } catch {}
  return null;
}

// ── Screen ──────────────────────────────────────────────────────────────────

function screenAlive() {
  return spawnSync("screen", ["-ls"], { encoding: "utf8" }).stdout.includes(`.${SESSION}`);
}

function injectCommand(cmd: string) {
  spawnSync("screen", ["-S", SESSION, "-X", "stuff", `${cmd}\r`]);
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  if (process.env.BUILD_SERVER !== "1") return;

  const token = loadControlToken();
  const ids   = chatIds();
  if (!token || !ids.length) return;

  let payload: any = {};
  try { payload = JSON.parse(await Bun.stdin.text()); } catch {}
  const transcript: string | undefined = payload.transcript_path;
  if (!transcript) return;

  const ctx = getContextInfo(transcript);
  if (ctx === null || ctx.pct < COMPACT_THRESHOLD) return;

  const isCritical = ctx.pct >= CLEAR_THRESHOLD;
  const cmd        = isCritical ? "/clear" : "/compact";
  const icon       = isCritical ? "🧹" : "🗜";
  const label      = isCritical
    ? `Контекст ${ctx.pct}% — критично, запускаю /clear (полный сброс)`
    : `Контекст ${ctx.pct}% — запускаю /compact`;

  for (const cid of ids) {
    try {
      await api(token, "sendMessage", { chat_id: cid, text: `${icon} ${label}` });
    } catch {}
  }

  if (screenAlive()) injectCommand(cmd);
}

main().catch(() => {});
