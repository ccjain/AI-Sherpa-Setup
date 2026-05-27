# AI Sherpa — Troubleshooting

---

## Installation Issues

### `node` not found after setup completes

**Symptom:** After `setup.bat` or `setup.sh` finishes, running `node --version` gives "command not found" or "not recognized".

**Cause:** Node.js was just installed, but your current terminal session was open before the PATH was updated.

**Fix:** Close the terminal completely and open a new one. Then run `node --version` again.

---

### `winget` not found (Windows) {#winget-not-found}

**Symptom:** `winget --version` gives "'winget' is not recognized as an internal or external command".

**Cause:** winget is not installed or not on PATH.

**Fix:**
1. Open the Microsoft Store
2. Search for "App Installer"
3. Install or update it
4. Restart your terminal and try again

---

### PowerShell execution policy error (Windows)

**Symptom:** Running `setup.bat` produces: "cannot be loaded because running scripts is disabled on this system".

**Cause:** Your machine's PowerShell execution policy blocks script execution. `setup.bat` uses `-ExecutionPolicy Bypass` to handle this, but some corporate group policies override it.

**Fix:** Ask your IT admin to allow script execution for your user account, or run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Then re-run `setup.bat`.

---

### `setup.bat` flashes and closes immediately (Windows)

**Symptom:** A black window appears and disappears in under a second.

**Cause:** PowerShell is not available, or the script failed immediately.

**Fix:**
1. Open PowerShell manually: Start → search "PowerShell" → Open
2. Run: `$PSVersionTable.PSVersion` — expected output: `5.x.x`
3. Then run setup manually:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\ai-sherpa\setup.ps1
   ```
4. The error message will now be visible in the window.

---

### `npx skillsadd` fails during setup

**Symptom:** Setup prints a skill install warning or fails during skill installation.

**Cause:** Network error, npm misconfiguration, or a temporary issue with skills.sh.

**Fix:**
1. Check your internet connection
2. Run the failed command manually: `npx skillsadd obra/superpowers`
3. If it fails with a proxy error, ask IT to whitelist `registry.npmjs.org` and `skills.sh`
4. Re-run setup: `setup.bat` (setup is idempotent — safe to run again)

---

### `claude` not found after setup

**Symptom:** `claude --version` gives "not recognized" even after setup finished successfully.

**Fix:**
1. Restart your terminal (most common fix)
2. If still not found, run manually: `npm install -g @anthropic-ai/claude-code`
3. If npm itself is not found, ensure Node.js 20+ is installed: `node --version`

---

### CLAUDE.md was not created in my project

**Symptom:** After setup completes, `CLAUDE.md` does not exist in your project directory.

**Likely cause:** The folder picker appeared but you selected the wrong folder, or dismissed it without selecting.

**Fix:** Re-run `setup.bat`. When the folder picker appears, select your project folder (not the AI Sherpa folder).

---

### `.claude/settings.json` was not created

**Symptom:** After setup, `$env:USERPROFILE\.claude\settings.json` (Windows) or `~/.claude/settings.json` (Linux/macOS) does not exist.

**Fix:** Re-run setup. If it still fails, create the directory and copy manually:

```powershell
# Windows
$dir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir }
Copy-Item "C:\tools\ai-sherpa\settings\settings-template.json" "$dir\settings.json"
```

```bash
# Linux/macOS
mkdir -p ~/.claude
cp ~/tools/ai-sherpa/settings/settings-template.json ~/.claude/settings.json
```

---

## Runtime Issues

### `/graphify` command not found inside Claude Code

**Symptom:** Typing `/graphify` in Claude Code gives an error or does nothing.

**Cause:** Graphify was not installed (Python pip was missing during setup), or Claude Code needs a restart.

**Fix:**
1. Exit Claude Code: `Ctrl+C`
2. Install Graphify manually:
   ```bash
   pip install graphifyy && graphify install
   ```
   On Windows, if `pip` is not found, install Python 3 from https://python.org first.
3. Restart Claude Code: `claude`
4. Try `/graphify` again

Alternatively, re-run `setup.bat` (or `setup.sh`) after Python is installed — setup installs Graphify automatically.

---

### Claude ignores CLAUDE.md rules

**Symptom:** Claude does not follow rules in CLAUDE.md — for example, skips the pre-flight check.

**Cause:** Very long CLAUDE.md files can cause Claude to deprioritize content near the end. AI Sherpa keeps each layer under its line limit to prevent this.

**Fix:**
1. Check line count: the combined total of all three CLAUDE.md layers should be under ~300 lines
2. Start a fresh Claude Code session
3. Keep project CLAUDE.md under 100 lines — move verbose notes to a separate doc

---

### Secrets protection not blocking `.env` access

**Symptom:** Claude reads a `.env` file when it should be blocked.

**Cause:** The `settings.json` deny rules may not have been written, or were overwritten.

**Fix:** Verify the settings file exists and has deny rules:
```powershell
# Windows
Get-Content "$env:USERPROFILE\.claude\settings.json" | ConvertFrom-Json
```
```bash
# Linux/macOS
cat ~/.claude/settings.json | python3 -m json.tool
```
Expected: `permissions.deny` array with at least 13 entries.

If missing, re-run setup or copy manually (see `.claude/settings.json` was not created above).
