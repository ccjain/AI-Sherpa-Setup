#!/usr/bin/env bash
# Claude Code status line — model, context bar, 5h rate-limit bar, 7d rate-limit bar.
# Installed to ~/.claude/hooks/ by setup.ps1 (Install-Hooks) and wired up via
# settings-template.json#statusLine.
#
# JSON parsing is done with node rather than jq: Node.js is already a hard
# dependency of AI Sherpa (all hooks run on it), while jq is NOT guaranteed to
# exist in Git Bash on Windows.
exec node -e '
let raw = "";
process.stdin.on("data", c => { raw += c; });
process.stdin.on("end", () => {
  let j = {};
  try { j = JSON.parse(raw); } catch (e) { /* render placeholders below */ }

  // 10-char progress bar from a 0-100 percentage; filled run rendered green
  const bar = pct => {
    const filled = Math.max(0, Math.min(10, Math.round(pct / 10)));
    return "\x1b[32m" + "█".repeat(filled) + "\x1b[0m" + "░".repeat(10 - filled);
  };

  // Countdown until a unix-epoch-seconds reset time: "3d4h" / "2h13m" / "42m".
  // Returns null when resets_at is absent so the countdown is simply omitted.
  const eta = t => {
    if (typeof t !== "number" || !isFinite(t)) return null;
    const d = Math.floor(t - Date.now() / 1000);
    if (d <= 0) return "now";
    const days = Math.floor(d / 86400);
    const hrs  = Math.floor((d % 86400) / 3600);
    const mins = Math.floor((d % 3600) / 60);
    if (days > 0) return days + "d" + hrs + "h";
    if (hrs  > 0) return hrs + "h" + mins + "m";
    return Math.max(1, mins) + "m";
  };

  const model = (j.model && (j.model.display_name || j.model.id)) || "unknown";

  const ctxPct = j.context_window ? j.context_window.used_percentage : null;
  const ctx = ctxPct != null
    ? "[" + bar(ctxPct) + "] " + Math.round(ctxPct) + "%"
    : "[░░░░░░░░░░] --%";

  let out = model + " | ctx:" + ctx;

  const fiveWin = j.rate_limits ? j.rate_limits.five_hour : null;
  if (fiveWin && fiveWin.used_percentage != null) {
    out += " | 5h:[" + bar(fiveWin.used_percentage) + "] " + Math.round(fiveWin.used_percentage) + "%";
    const e = eta(fiveWin.resets_at);
    if (e) out += " (" + e + ")";
  }

  const weekWin = j.rate_limits ? j.rate_limits.seven_day : null;
  if (weekWin && weekWin.used_percentage != null) {
    out += " | 7d:[" + bar(weekWin.used_percentage) + "] " + Math.round(weekWin.used_percentage) + "%";
    const e = eta(weekWin.resets_at);
    if (e) out += " (" + e + ")";
  }

  process.stdout.write(out);
});
'
