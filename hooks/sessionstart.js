#!/usr/bin/env node
// AI Sherpa — SessionStart hook
//
// Activates AI Sherpa domain rules for the conversation's working directory.
//
// Flow (matches docs/superpowers/specs/2026-06-01-per-session-domain-selection-design.md):
//
//   1. If <cwd>/.claude/ai-sherpa-domains.json exists with domains -> Case A
//      emit those domains' rules silently.
//   2. If selection file exists with domains:[] -> Case C
//      opted out; emit nothing.
//   3. Else run Layer 1 file-fingerprint detection:
//        - one or more domains found -> Case B1: emit banner + rules
//        - nothing found             -> Case B2: emit "ask user" reminder
//
// Hard rules:
//   - Must always exit 0; the session must never fail because of us.
//   - No writes to disk. Claude writes the selection file based on the
//     embedded instructions, so the audit trail lives in the transcript.
//   - Bail early if cwd is the user's $HOME / $USERPROFILE — running
//     `claude` from home shouldn't fingerprint random files there.

const fs = require("fs");
const path = require("path");

const cwd = process.cwd();
const home = process.env.USERPROFILE || process.env.HOME || "";

const STATE_DIR = path.join(home, ".claude", "ai-sherpa");
const RUNTIME_DOMAINS = path.join(STATE_DIR, "domains");
const SELECTION_FILE = path.join(cwd, ".claude", "ai-sherpa-domains.json");

// Bail-early guards.
if (!home || cwd === home) {
  process.exit(0);
}

try {
  main();
} catch (err) {
  console.error("[ai-sherpa hook] non-fatal:", err && err.message);
}
process.exit(0);

// ----- main -----

function main() {
  if (fs.existsSync(SELECTION_FILE)) {
    let sel;
    try {
      sel = JSON.parse(fs.readFileSync(SELECTION_FILE, "utf8"));
    } catch (parseErr) {
      console.error(
        "[ai-sherpa hook] malformed JSON at",
        SELECTION_FILE,
        "- treating as missing:",
        parseErr.message
      );
      runDetectionPath();
      return;
    }
    const domains = Array.isArray(sel.domains) ? sel.domains.filter(s => typeof s === "string") : [];
    if (domains.length > 0) {
      emitDomainRules(domains, null);
    }
    // Case C: empty domains -> emit nothing.
    return;
  }

  runDetectionPath();
}

function runDetectionPath() {
  const { domains, signals } = detect(cwd);
  if (domains.length > 0) {
    emitDomainRules(domains, { kind: "detected", domains, signals });
  } else {
    emitAskUserBanner();
  }
}

// ----- emit -----

function emitDomainRules(domains, banner) {
  const out = process.stdout;
  out.write("<system-reminder>\n");
  out.write("AI Sherpa — domain rules active for this conversation.\n");

  if (banner && banner.kind === "detected") {
    const signalsLine = banner.signals.length ? banner.signals.join(", ") : "(none)";
    out.write("\n");
    out.write("Detected domain(s) for this project: " + banner.domains.join(", ") + "\n");
    out.write("Triggered by: " + signalsLine + "\n");
    out.write("\n");
    out.write("On your first response to the user, briefly say:\n");
    out.write(
      `  "I see ${describeStack(banner.signals)} — activating ${banner.domains.join(" + ")} rules. Type /ai-sherpa-domains to change."\n`
    );
    out.write("\n");
    out.write("Then write " + SELECTION_FILE + " with the following content (create the\n");
    out.write(".claude/ directory first if needed):\n");
    out.write(
      "  " +
        JSON.stringify({
          version: 1,
          domains: banner.domains,
          detected: true,
          detected_from: banner.signals,
          user_confirmed: false,
          updated_at: new Date().toISOString(),
        }) +
        "\n"
    );
    out.write("\n");
  }

  for (const d of domains) {
    const f = path.join(RUNTIME_DOMAINS, d, "CLAUDE.md");
    if (!fs.existsSync(f)) {
      console.error("[ai-sherpa hook] domain '" + d + "' not in runtime cache at " + f + " - skipping");
      continue;
    }
    const body = fs.readFileSync(f, "utf8");
    out.write("\n--- BEGIN domain rules: " + d + " ---\n");
    out.write(body);
    if (!body.endsWith("\n")) out.write("\n");
    out.write("--- END domain rules: " + d + " ---\n");
  }

  out.write("</system-reminder>\n");
}

function emitAskUserBanner() {
  const out = process.stdout;
  out.write("<system-reminder>\n");
  out.write("AI Sherpa — no domain selected for this project, and detection found no\n");
  out.write("recognized stack signals.\n");
  out.write("\n");
  out.write("On your first response to the user, ask them which AI Sherpa domain(s)\n");
  out.write("apply. Available domains:\n");
  out.write("  embedded, web, frontend, ai, data, devops,\n");
  out.write("  marketing, sales, finance, service, procurement\n");
  out.write("Also offer 'skip' to opt out (no domain rules for this project).\n");
  out.write("\n");
  out.write("Then write " + SELECTION_FILE + " with the user's answer. Schema:\n");
  out.write(
    '  {"version":1,"domains":[...],"detected":false,"user_confirmed":true,"updated_at":"<ISO>"}\n'
  );
  out.write("Use domains:[] for opt-out.\n");
  out.write("</system-reminder>\n");
}

function describeStack(signals) {
  // Turn ["package.json:next","package.json:langchain"] into "Next.js + langchain".
  // Best-effort cosmetic prettifier; if it can't, fall back to listing signals verbatim.
  const pretty = {
    next: "Next.js",
    react: "React",
    vue: "Vue",
    angular: "Angular",
    svelte: "Svelte",
    nuxt: "Nuxt",
    gatsby: "Gatsby",
    express: "Express",
    fastify: "Fastify",
    "@nestjs/": "NestJS",
    koa: "Koa",
    hapi: "Hapi",
    langchain: "langchain",
    anthropic: "Anthropic SDK",
    openai: "OpenAI SDK",
    "llama-index": "llama-index",
    crewai: "CrewAI",
    autogen: "AutoGen",
    pandas: "pandas",
    "scikit-learn": "scikit-learn",
    numpy: "numpy",
    pytorch: "PyTorch",
    tensorflow: "TensorFlow",
    polars: "polars",
    xgboost: "XGBoost",
  };
  const labels = new Set();
  for (const s of signals) {
    const colon = s.indexOf(":");
    const token = colon >= 0 ? s.slice(colon + 1) : s;
    if (pretty[token]) labels.add(pretty[token]);
    else if (token === "Zephyr" || token === "Arduino" || token === "PlatformIO" || token === "ESP-IDF" || token === "Mbed OS") {
      labels.add(token);
    } else {
      labels.add(token);
    }
  }
  return [...labels].join(" + ");
}

// ----- detect -----

function detect(root) {
  const domains = new Set();
  const signals = [];

  // Embedded — Zephyr markers
  for (const f of ["west.yml", "prj.conf", "Kconfig"]) {
    if (existsAt(root, f)) {
      domains.add("embedded");
      signals.push(f + ":Zephyr");
    }
  }
  if (isDir(path.join(root, "boards"))) {
    domains.add("embedded");
    signals.push("boards/:Zephyr");
  }

  // Embedded — other vendor SDKs
  if (existsAt(root, "platformio.ini")) {
    domains.add("embedded");
    signals.push("platformio.ini:PlatformIO");
  }
  if (existsAt(root, "mbed_app.json")) {
    domains.add("embedded");
    signals.push("mbed_app.json:Mbed OS");
  }
  for (const f of ["sdkconfig", "sdkconfig.defaults"]) {
    if (existsAt(root, f)) {
      domains.add("embedded");
      signals.push(f + ":ESP-IDF");
    }
  }

  // Embedded — file-extension heuristics (root and one level deep)
  if (anyFileMatches(root, /\.ino$/i, { rootOnly: true })) {
    domains.add("embedded");
    signals.push("*.ino:Arduino");
  }
  const cFamily = /\.(c|cc|cpp|cxx)$/i;
  const hFamily = /\.(h|hpp|hxx)$/i;
  if (anyFileMatches(root, cFamily, { rootOnly: false, allowedDirs: ["src"] })) {
    domains.add("embedded");
    signals.push("*.c/cpp:C/C++");
  }
  if (anyFileMatches(root, hFamily, { rootOnly: false, allowedDirs: ["src", "include"] })) {
    domains.add("embedded");
    signals.push("*.h/hpp:headers");
  }
  if (anyFileMatches(root, /\.ld$/i, { rootOnly: true })) {
    domains.add("embedded");
    signals.push("*.ld:linker script");
  }
  if (existsAt(root, "Makefile")) {
    const mk = readSmall(path.join(root, "Makefile"));
    if (/\b(arm-none-eabi-|avr-gcc|xtensa-|riscv\d*-)/i.test(mk)) {
      domains.add("embedded");
      signals.push("Makefile:cross-compile");
    }
  }

  // Web/frontend — package.json dependencies
  const pkgPath = path.join(root, "package.json");
  if (fs.existsSync(pkgPath)) {
    let pkg;
    try {
      pkg = JSON.parse(readSmall(pkgPath));
    } catch {
      pkg = null;
    }
    if (pkg) {
      const deps = Object.assign(
        {},
        pkg.dependencies || {},
        pkg.devDependencies || {},
        pkg.peerDependencies || {}
      );
      const has = (name) => Object.prototype.hasOwnProperty.call(deps, name);
      const hasPrefix = (prefix) =>
        Object.keys(deps).some((k) => k.startsWith(prefix));

      const frontendFrameworks = [
        "next",
        "react",
        "vue",
        "angular",
        "@angular/core",
        "svelte",
        "nuxt",
        "gatsby",
      ];
      for (const name of frontendFrameworks) {
        if (has(name)) {
          domains.add("web");
          domains.add("frontend");
          signals.push("package.json:" + normalize(name));
        }
      }
      // Note: @nestjs/ is prefix-matched (@nestjs/core, @nestjs/common ...)
      const backendFrameworks = ["express", "fastify", "koa", "hapi"];
      for (const name of backendFrameworks) {
        if (has(name)) {
          domains.add("web");
          signals.push("package.json:" + name);
        }
      }
      if (hasPrefix("@nestjs/")) {
        domains.add("web");
        signals.push("package.json:@nestjs/");
      }
    }
  }

  // AI / data — requirements.txt or pyproject.toml
  const aiLibs = ["langchain", "anthropic", "openai", "llama-index", "crewai", "autogen"];
  const dataLibs = ["pandas", "scikit-learn", "numpy", "pytorch", "tensorflow", "polars", "xgboost"];
  const pythonText = readManySmall([
    path.join(root, "requirements.txt"),
    path.join(root, "pyproject.toml"),
  ]);
  if (pythonText) {
    for (const lib of aiLibs) {
      if (pythonRequiresContains(pythonText, lib)) {
        domains.add("ai");
        signals.push("python:" + lib);
      }
    }
    for (const lib of dataLibs) {
      if (pythonRequiresContains(pythonText, lib)) {
        domains.add("data");
        signals.push("python:" + lib);
      }
    }
  }

  // Devops
  for (const f of ["Dockerfile", "docker-compose.yml", "docker-compose.yaml"]) {
    if (existsAt(root, f)) {
      domains.add("devops");
      signals.push(f + ":container");
    }
  }
  for (const d of ["kubernetes", "k8s", "helm", "terraform"]) {
    if (isDir(path.join(root, d))) {
      domains.add("devops");
      signals.push(d + "/:infra");
    }
  }
  if (anyFileMatches(root, /\.tf$/i, { rootOnly: true })) {
    domains.add("devops");
    signals.push("*.tf:terraform");
  }
  if (isDir(path.join(root, ".github", "workflows"))) {
    domains.add("devops");
    signals.push(".github/workflows/:CI");
  }

  return { domains: [...domains], signals };
}

// ----- helpers -----

const SKIP_DIRS = new Set([
  "node_modules",
  "venv",
  ".venv",
  "dist",
  "build",
  ".git",
  ".next",
  "__pycache__",
  "target",
  "out",
]);

function existsAt(root, name) {
  try {
    return fs.existsSync(path.join(root, name));
  } catch {
    return false;
  }
}

function isDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function readSmall(file) {
  try {
    const stat = fs.statSync(file);
    // Don't slurp big files into memory; package.json / requirements.txt /
    // pyproject.toml / Makefile are tiny in any real project.
    if (stat.size > 512 * 1024) return "";
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function readManySmall(files) {
  return files.map(readSmall).join("\n");
}

function anyFileMatches(root, regex, opts) {
  const rootOnly = !!(opts && opts.rootOnly);
  const allowedDirs = (opts && opts.allowedDirs) || [];
  // Root pass
  let entries;
  try {
    entries = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return false;
  }
  for (const e of entries) {
    if (e.isFile() && regex.test(e.name)) return true;
  }
  if (rootOnly) return false;
  // One-level-deep pass into allowed subdirs only (e.g. src/, include/)
  for (const dirName of allowedDirs) {
    const sub = path.join(root, dirName);
    if (!isDir(sub) || SKIP_DIRS.has(dirName)) continue;
    let subEntries;
    try {
      subEntries = fs.readdirSync(sub, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of subEntries) {
      if (e.isFile() && regex.test(e.name)) return true;
    }
  }
  return false;
}

function pythonRequiresContains(text, libName) {
  // Match requirements-style lines and pyproject deps.
  // We look for the library name at a word boundary, optionally preceded by quote,
  // followed by comparison/version/space/end. Catches:
  //   langchain==0.1.0
  //   "langchain"
  //   langchain >= 0.1
  //   langchain
  // Tolerates underscore vs hyphen variation (scikit-learn / scikit_learn).
  const escaped = libName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const variant = escaped.replace(/-/g, "[-_]");
  const re = new RegExp("(^|[\"'\\s,\\[])" + variant + "(\\s*[=<>!~]|\\s*[\"',\\]]|\\s*$)", "im");
  return re.test(text);
}

function normalize(name) {
  // @angular/core -> angular
  if (name.startsWith("@angular/")) return "angular";
  return name;
}
