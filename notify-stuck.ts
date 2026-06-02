#!/usr/bin/env bun
// Вызывается из launchd-boot.sh когда Claude завис (нет ответа > STUCK_MINUTES).
// Аргументы: <минут_прошло> <имя_проекта>
import { loadControlToken, chatIds, api } from "./tglib.ts";

const minutes = parseInt(process.argv[2] ?? "15", 10);
const proj    = process.argv[3] ?? "проект";

const token = loadControlToken();
const ids   = chatIds();
if (!token || ids.length === 0) process.exit(0);

const text = `⚠️ Claude не отвечает ${minutes} мин — ${proj}\n\nВозможно, ждёт разрешения или завис.`;
const replyMarkup = {
  inline_keyboard: [[
    { text: "🛑 Прервать (Esc)",  callback_data: "bs:stop"    },
    { text: "🔄 Перезапустить",   callback_data: "bs:restart" },
  ]],
};

for (const cid of ids) {
  try {
    await api(token, "sendMessage", {
      chat_id:      cid,
      text,
      reply_markup: JSON.stringify(replyMarkup),
    });
  } catch {}
}
