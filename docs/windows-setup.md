# AI Sherpa — Windows Setup Guide

For the quick-start version, see [user-guide.md](user-guide.md). This guide covers Windows-specific steps and common issues.

---

## What Gets Installed Automatically

`setup.bat` installs the following if not already present:

| Tool | How installed | Required |
|---|---|---|
| Node.js 20 | winget (Microsoft app store CLI) | Yes |
| Git | winget | Yes |
| Claude Code CLI | npm install -g | Yes |
| AI skills | npx skillsadd | Yes |

You do not need to install these manually unless `setup.bat` fails. See [Troubleshooting](troubleshooting.md) if it does.

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ (pre-installed on Windows 10/11 — no action needed)
- `winget` (pre-installed on Windows 11; available on Windows 10 via Microsoft Store)
- Internet access

---

## Step-by-Step

### Step 1 — Verify winget is available

Open Command Prompt or PowerShell and run:
```
winget --version
```
Expected: `v1.x.x`

If you get "winget is not recognized", see [winget-not-found](troubleshooting.md#winget-not-found).

### Step 2 — Clone AI Sherpa (one-time, anywhere on your machine)

```
git clone <ai-sherpa-repo-url> C:\tools\ai-sherpa
```

If Git is not yet installed, download from https://git-scm.com and install it first.

### Step 3 — Open a terminal in your project directory

In File Explorer: navigate to your project folder, hold **Shift**, right-click the folder → "Open PowerShell window here" or "Open Command Prompt here".

Or from any terminal:
```
cd C:\path\to\your-project
```

**Do NOT run setup.bat from inside `C:\tools\ai-sherpa`.** Run it from your project directory.

### Step 4 — Run setup.bat

```
C:\tools\ai-sherpa\setup.bat
```

You will be asked two questions:
1. Which domain? (Enter 1–5)
2. New or existing project? (Enter 1 or 2)

Setup takes 2–5 minutes. You will see `AI Sherpa Setup Complete` when done.

### Step 5 — Restart your terminal

Close and reopen your terminal. This is required for Node.js and Git to appear on your PATH.

### Step 6 — Verify the installation

```powershell
node --version      # Expected: v20.x.x
git --version       # Expected: git version 2.x.x
claude --version    # Expected: a version number
```

Check secrets protection is active:
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" | ConvertFrom-Json
```
Expected: shows a `permissions.deny` array containing `.env` rules.

Check CLAUDE.md was installed in your project:
```powershell
Test-Path ".\CLAUDE.md"
```
Expected: `True`

### Step 7 — Index your codebase

Start Claude Code:
```
claude
```

Inside Claude Code, run:
```
/graphify
```

This indexes your codebase and dramatically reduces token cost for future sessions. Run it once after setup, and again after large codebase changes.

---

## Updating AI Sherpa

```
C:\tools\ai-sherpa\setup.bat --update
```

Run this when the AI Sherpa team announces an update. It updates skills and settings but never touches your project's CLAUDE.md.
