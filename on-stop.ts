#!/usr/bin/env bun
// Оркестратор Stop-хуков: читает stdin ОДИН раз и передаёт payload
// в notify-stop.ts и compact-check.ts через отдельные процессы.
// Решает баг "&&-chain": при `cmd1 && cmd2` второй процесс получает
// пустой stdin, потому что Claude Code уже закрыл pipe после cmd1.
import { writeFileSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const BS  = join(homedir(), ".claude", "buildserver");
const BUN = join(homedir(), ".bun", "bin", "bun");
const TMP = join(BS, "state", `.stop-payload-${Date.now()}.json`);

const input = await Bun.stdin.text();

try {
  writeFileSync(TMP, input);

  for (const script of ["notify-stop.ts", "compact-check.ts"]) {
    const file = Bun.file(TMP);
    const proc = Bun.spawn([BUN, join(BS, script)], {
      stdin:  file,
      stdout: "inherit",
      stderr: "inherit",
      env:    { ...process.env },
    });
    await proc.exited;
  }
} finally {
  try { unlinkSync(TMP); } catch {}
}
