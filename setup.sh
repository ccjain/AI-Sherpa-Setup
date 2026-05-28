#!/usr/bin/env bash
# Re-exec under bash if invoked via `sh setup.sh` (dash on Ubuntu/WSL lacks bashisms used below)
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: this script requires bash. Install bash or run: bash $0" >&2
        exit 1
    fi
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[AI Sherpa]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[AI Sherpa]${NC} $1"; }
log_error() { echo -e "${RED}[AI Sherpa]${NC} $1"; }

SKIPPED_STEPS=()
add_skipped_step() {
  # args: name | reason | manual_install
  SKIPPED_STEPS+=("$1|$2|$3")
}

INSTALL_FAILURES=()
add_install_failure() {
  INSTALL_FAILURES+=("$1")
}
show_skipped_steps_report() {
  if [[ ${#SKIPPED_STEPS[@]} -eq 0 ]]; then return; fi
  echo ""
  echo -e "${YELLOW}======================================================${NC}"
  echo -e "${YELLOW}  OPTIONAL STEPS SKIPPED (${#SKIPPED_STEPS[@]})${NC}"
  echo -e "${YELLOW}  Setup continued, but these features are unavailable:${NC}"
  echo -e "${YELLOW}======================================================${NC}"
  for entry in "${SKIPPED_STEPS[@]}"; do
    IFS='|' read -r name reason manual <<< "$entry"
    echo ""
    echo -e "${YELLOW}  > $name${NC}"
    echo "    Reason: $reason"
    echo "    Install manually: $manual"
  done
  echo ""
  echo -e "${YELLOW}======================================================${NC}"
  echo ""
}

check_command() { command -v "$1" &>/dev/null; }

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
  [[ -f /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version && return 0
  return 1
}

# Detect WSL+Windows hybrid: claude binary lives on a Windows mount (/mnt/c/...).
# In this mode, claude's state directory is the Windows user's .claude/, not WSL home.
is_windows_claude_hybrid() {
  is_wsl || return 1
  local cp
  cp=$(command -v claude 2>/dev/null) || return 1
  [[ "$cp" == /mnt/[cC]/* ]]
}

# Resolve the Windows-side .claude/ directory as a WSL path.
# Echoes e.g. /mnt/c/Users/Admin/.claude  — empty if we can't determine.
resolve_windows_claude_home() {
  local cp
  cp=$(command -v claude 2>/dev/null) || return 1
  if [[ "$cp" =~ ^(/mnt/[cC])/Users/([^/]+)/ ]]; then
    echo "${BASH_REMATCH[1]}/Users/${BASH_REMATCH[2]}/.claude"
  fi
}

# EFFECTIVE_HOME = directory whose .claude/ subdir is the active config root.
# Defaults to $HOME, but in WSL+Windows-claude hybrid mode it points at the
# Windows user's home dir (e.g. /mnt/c/Users/Admin).
EFFECTIVE_HOME="$HOME"

write_settings() {
  local settings_dir="$EFFECTIVE_HOME/.claude"
  local settings_file="$settings_dir/settings.json"
  mkdir -p "$settings_dir"
  if [[ -f "$settings_file" ]]; then
    cp "$settings_file" "${settings_file}.bak"
    log_warn "Backed up existing settings.json to ${settings_file}.bak"
  fi
  cp "$SCRIPT_DIR/settings/settings-template.json" "$settings_file"
  log_info "Secrets protection written to $settings_file"
}

write_project_settings() {
  local project_settings_dir="$PWD/.claude"
  local project_settings_file="$project_settings_dir/settings.json"
  mkdir -p "$project_settings_dir"
  if [[ -f "$project_settings_file" ]]; then
    cp "$project_settings_file" "${project_settings_file}.bak"
    log_warn "Backed up existing project settings.json"
  fi
  cp "$SCRIPT_DIR/settings/settings-template.json" "$project_settings_file"
  log_info "Project-level secrets protection written to $project_settings_file"
}

copy_claude_md() {
  local domain="$1" project_type="$2"
  local source="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  local target="$PWD/CLAUDE.md"
  if [[ "$project_type" == "existing" && -f "$target" ]]; then
    log_warn "Appending domain rules to existing CLAUDE.md (original preserved)"
    printf '\n---\n<!-- AI Sherpa domain rules — do not edit below this line -->\n' >> "$target"
    cat "$source" >> "$target"
  else
    cp "$source" "$target"
  fi
  log_info "Domain CLAUDE.md installed at $target"
}

write_global_claude_md() {
  local domain="$1"
  local source="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$source" ]]; then
    log_error "Domain CLAUDE.md not found at: $source"
    exit 1
  fi
  local claude_dir="$EFFECTIVE_HOME/.claude"
  local target="$claude_dir/CLAUDE.md"
  mkdir -p "$claude_dir"
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.bak"
    log_warn "Backed up existing $target to $target.bak"
  fi
  cp "$source" "$target"
  log_info "Domain rules written to $target (active for all projects)"
}

# Parse plugins.json for a given section ("global" or domain name).
# Outputs pipe-delimited lines: type|name|source
# Returns non-zero and prints error if plugins.json is missing or invalid.
_read_plugins() {
  local section="$1"
  local config_file="$SCRIPT_DIR/plugins.json"
  if [[ ! -f "$config_file" ]]; then
    log_error "plugins.json not found at $config_file" >&2
    return 1
  fi
  node -e "
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => { raw += d; });
process.stdin.on('end', () => {
  let config;
  try { config = JSON.parse(raw); }
  catch (e) { process.stderr.write('Failed to parse plugins.json: ' + e.message + '\n'); process.exit(1); }
  const section = '$section';
  const plugins = section === 'global'
    ? (config.global || [])
    : ((config.domains && config.domains[section]) || []);
  plugins.forEach(p => {
    if (p.marketplace) process.stdout.write('marketplace|' + p.name + '|' + p.marketplace + '\n');
    else if (p.github)  process.stdout.write('github|'      + p.name + '|' + p.github      + '\n');
  });
});
" < "$config_file"
}

# Install one plugin entry (args: type name source)
_install_plugin() {
  local type="$1" name="$2" source="$3"
  if [[ "$type" == "marketplace" ]]; then
    if ! claude plugin install "$name@$source" --scope user; then
      log_warn "$name install failed — see error above."
      add_install_failure "$name@$source"
    fi
  elif [[ "$type" == "github" ]]; then
    claude plugin marketplace add "https://github.com/$source" 2>/dev/null || true
    if ! claude plugin install "$name" --scope user; then
      log_warn "$name install failed — see error above."
      add_install_failure "$name"
    fi
  fi
}

register_marketplaces() {
  local domain="${1:-}"
  local config_file="$SCRIPT_DIR/plugins.json"
  if [[ ! -f "$config_file" ]]; then return; fi
  local entries
  entries=$(node -e "
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => { raw += d; });
process.stdin.on('end', () => {
  let config;
  try { config = JSON.parse(raw); } catch (e) { process.exit(0); }
  const section = '$domain';

  // Collect marketplace names actually referenced by global + selected domain plugins
  const needed = new Set();
  (config.global || []).forEach(p => { if (p.marketplace) needed.add(p.marketplace); });
  if (section) {
    (config.domains && config.domains[section] || []).forEach(p => { if (p.marketplace) needed.add(p.marketplace); });
  }

  const ms = config.marketplaces || [];
  ms.forEach(m => {
    const repo = typeof m === 'string' ? m : (m.repo || '');
    const name = typeof m === 'string' ? '' : (m.name || '');
    if (needed.has(name)) {
      process.stdout.write(repo + '|' + name + '\n');
    }
  });
});
" < "$config_file")
  if [[ -z "$entries" ]]; then return; fi
  while IFS='|' read -r repo name; do
    [[ -z "$repo" ]] && continue
    log_info "Registering marketplace: $repo"
    claude plugin marketplace add "$repo" 2>/dev/null || true
    if [[ -n "$name" ]]; then
      claude plugin marketplace update "$name" 2>/dev/null \
        || log_warn "Could not update marketplace $name — domain plugins may fail."
    fi
  done <<< "$entries"
}

install_core_skills() {
  log_info "Installing core skills (this may take 1-2 minutes)..."
  local plugin_list
  plugin_list=$(_read_plugins "global") || { log_error "Cannot read plugins.json — aborting."; exit 1; }
  if [[ -z "$plugin_list" ]]; then
    log_warn "No global plugins defined in plugins.json"
    return
  fi
  while IFS='|' read -r type name source; do
    [[ -z "$type" ]] && continue
    _install_plugin "$type" "$name" "$source"
  done <<< "$plugin_list"
  log_info "Core skills installed."
}

install_domain_skills() {
  local domain="$1"
  local plugin_list
  plugin_list=$(_read_plugins "$domain") || { log_error "Cannot read plugins.json — aborting."; exit 1; }
  if [[ -z "$plugin_list" ]]; then
    log_info "No additional skills for $domain — core skills + CLAUDE.md rules apply."
    return
  fi
  log_info "Installing $domain skills..."
  while IFS='|' read -r type name source; do
    [[ -z "$type" ]] && continue
    _install_plugin "$type" "$name" "$source"
  done <<< "$plugin_list"
}

# Read plugins.json "skills" section (global + selected domain).
# Outputs pipe-delimited lines: repo|subpath
_read_skills() {
  local domain="${1:-}"
  local config_file="$SCRIPT_DIR/plugins.json"
  [[ -f "$config_file" ]] || return 0
  node -e "
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => { raw += d; });
process.stdin.on('end', () => {
  let config;
  try { config = JSON.parse(raw); } catch (e) { process.exit(0); }
  const domain = '$domain';
  const skills = config.skills || {};
  const entries = []
    .concat(skills.global || [])
    .concat((domain && skills[domain]) || []);
  entries.forEach(e => {
    const repo = e.repo || '';
    const subpath = e.subpath || 'skills';
    if (repo) process.stdout.write(repo + '|' + subpath + '\n');
  });
});
" < "$config_file"
}

install_skills() {
  local domain="${1:-}"
  local entries
  entries=$(_read_skills "$domain")
  [[ -z "$entries" ]] && return 0

  if ! check_command git; then
    log_warn "git not on PATH — cannot install raw skills (plugins.json 'skills' section)."
    return 0
  fi

  local skills_dir="$EFFECTIVE_HOME/.claude/skills"
  mkdir -p "$skills_dir"

  while IFS='|' read -r repo subpath; do
    [[ -z "$repo" ]] && continue
    local slug tmp
    slug=$(echo "$repo" | tr '/' '-')
    tmp=$(mktemp -d -t "ai-sherpa-skill-${slug}.XXXXXX")
    log_info "Cloning skills from $repo..."
    if ! git clone --depth 1 "https://github.com/$repo" "$tmp" >/dev/null 2>&1; then
      log_warn "Failed to clone $repo — skipping its skills."
      rm -rf "$tmp"
      add_install_failure "skills:$repo"
      continue
    fi
    if [[ ! -d "$tmp/$subpath" ]]; then
      log_warn "Subpath '$subpath' not found in $repo — skipping."
      rm -rf "$tmp"
      add_install_failure "skills:$repo (missing subpath: $subpath)"
      continue
    fi
    cp -rf "$tmp/$subpath/"* "$skills_dir/"
    rm -rf "$tmp"
    log_info "Installed skills from $repo into $skills_dir"
  done <<< "$entries"
}

print_summary() {
  local domain="$1" user_level="${2:-false}"
  echo -e "\n${CYAN}======================================================${NC}"
  echo -e "${CYAN}  AI Sherpa Setup Complete${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo "  Domain:   $domain"
  echo "  Settings: $EFFECTIVE_HOME/.claude/settings.json  (secrets protection active)"
  if [[ "$user_level" == true ]]; then
    echo "  Rules:    $EFFECTIVE_HOME/.claude/CLAUDE.md  (active for all projects)"
  else
    echo "  Settings: $PWD/.claude/settings.json   (project-level)"
    echo "  Rules:    CLAUDE.md installed in $PWD"
  fi
  echo ""
  echo "  Next steps:"
  echo "  1. Start Claude Code:   claude"
  echo "  2. Code-review graph runs in auto-mode via SessionStart hook (no manual step)."
  echo "  3. Start coding — AI Sherpa rules are active automatically"
  echo ""
  echo "  Update later: bash \"$SCRIPT_DIR/setup.sh\" --update"
  echo -e "${CYAN}======================================================${NC}\n"
}

resolve_pip_command() {
  if check_command pip3; then echo "pip3"; return; fi
  if check_command pip;  then echo "pip";  return; fi
  echo ""
}

install_git_via_pkg_manager() {
  log_info "Git not found. Attempting to install via system package manager..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if check_command brew; then brew install git; return $?
    else return 1; fi
  elif check_command apt-get; then sudo apt-get update -qq && sudo apt-get install -y git; return $?
  elif check_command dnf;     then sudo dnf install -y git; return $?
  fi
  return 1
}

install_python() {
  log_info "Python pip not found. Attempting to install Python 3..."
  local rc=1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if check_command brew; then brew install python; rc=$?
    else rc=1; fi
  elif check_command apt-get; then sudo apt-get update -qq && sudo apt-get install -y python3 python3-pip; rc=$?
  elif check_command dnf;     then sudo dnf install -y python3 python3-pip; rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    log_warn "Automatic Python install failed."
    add_skipped_step \
      "code-review-graph (auto-mode code review indexing)" \
      "Automatic Python install failed (no supported package manager, or install command exited non-zero)" \
      "Install Python 3 from https://python.org (or via your package manager), then re-run setup.sh"
    return 1
  fi
  log_info "Python installed."
  return 0
}

ensure_pipx() {
  if check_command pipx; then return 0; fi
  log_info "pipx not found. Installing (required by PEP 668 on modern Linux)..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if check_command brew; then brew install pipx && pipx ensurepath && return 0; fi
  elif check_command apt-get; then
    sudo apt-get install -y pipx && pipx ensurepath && return 0
  elif check_command dnf; then
    sudo dnf install -y pipx && pipx ensurepath && return 0
  fi
  return 1
}

has_windows_interop() {
  command -v powershell.exe >/dev/null 2>&1
}

install_code_review_graph_windows_side() {
  if ! has_windows_interop; then
    log_warn "Windows interop (powershell.exe) not available from this WSL distro."
    add_skipped_step \
      "code-review-graph (auto-mode code review indexing)" \
      "Hybrid mode requires Windows interop, which is disabled in this WSL distro" \
      "From Windows PowerShell: winget install Python.Python.3.12 ; py -m pip install code-review-graph ; code-review-graph install"
    return 1
  fi

  log_info "Installing code-review-graph on Windows (via powershell.exe from WSL)..."

  # Find a working Windows pip invocation. Order:
  #   1. pip              - direct, if pip.exe is on PATH
  #   2. py -m pip        - Windows py launcher (works for python.org installs)
  #   3. python -m pip    - only if python.exe is the real Python (NOT the MS Store stub)
  # The MS Store stub at AppData\Local\Microsoft\WindowsApps\python.exe intercepts
  # `python` on PATH and just prints a help message; py.exe is the reliable fallback.
  find_windows_pip() {
    if powershell.exe -NoProfile -Command 'pip --version'           >/dev/null 2>&1; then echo "pip"; return; fi
    if powershell.exe -NoProfile -Command 'py -m pip --version'     >/dev/null 2>&1; then echo "py -m pip"; return; fi
    if powershell.exe -NoProfile -Command 'python -m pip --version' >/dev/null 2>&1; then echo "python -m pip"; return; fi
    echo ""
  }

  local pip_cmd
  pip_cmd=$(find_windows_pip)

  if [[ -z "$pip_cmd" ]]; then
    log_info "Windows pip not found via pip / py -m pip / python -m pip. Installing Python 3.12 via winget..."
    # winget exits non-zero when the package is already at latest version
    # ("No newer package versions are available"). That's not a failure for our
    # purposes - we only care whether pip becomes reachable after this step.
    powershell.exe -NoProfile -Command 'winget install Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements' || true
    pip_cmd=$(find_windows_pip)
    if [[ -z "$pip_cmd" ]]; then
      log_warn "Could not find a working Windows pip after install attempt."
      add_skipped_step \
        "code-review-graph (auto-mode code review indexing)" \
        "Windows Python may be installed but pip is not reachable (often: Microsoft Store python stub intercepts python.exe, and py.exe / pip.exe are not on PATH)" \
        "From Windows PowerShell: py -m pip install code-review-graph ; code-review-graph install   (or install Python from https://python.org with 'Add to PATH' checked)"
      return 1
    fi
  fi

  log_info "Installing code-review-graph on Windows (using: $pip_cmd)..."
  if ! powershell.exe -NoProfile -Command "$pip_cmd install --quiet code-review-graph"; then
    log_warn "Windows pip install code-review-graph failed."
    add_skipped_step \
      "code-review-graph (auto-mode code review indexing)" \
      "Windows pip install code-review-graph failed (using: $pip_cmd)" \
      "From Windows PowerShell: $pip_cmd install code-review-graph ; code-review-graph install"
    return 1
  fi

  # code-review-graph.exe is installed into Python's Scripts directory, which is often
  # NOT on Windows PATH. Resolve the absolute path via Python's sysconfig
  # and invoke it directly. Try the standard Scripts dir, then the user one.
  local py_cmd="py"
  case "$pip_cmd" in
    "py -m pip")     py_cmd="py" ;;
    "python -m pip") py_cmd="python" ;;
    "pip")           py_cmd="python" ;;
  esac

  local sys_scripts user_scripts graphify_exe=""
  sys_scripts=$(powershell.exe -NoProfile -Command "$py_cmd -c \"import sysconfig; print(sysconfig.get_path('scripts'))\"" 2>/dev/null | tr -d '\r\n')
  user_scripts=$(powershell.exe -NoProfile -Command "$py_cmd -c \"import site, os; print(os.path.join(site.getuserbase(), 'Scripts'))\"" 2>/dev/null | tr -d '\r\n')

  if [[ -n "$sys_scripts" ]] && \
     powershell.exe -NoProfile -Command "Test-Path -LiteralPath '$sys_scripts\\code-review-graph.exe'" 2>/dev/null | grep -qi true; then
    graphify_exe="$sys_scripts\\code-review-graph.exe"
  elif [[ -n "$user_scripts" ]] && \
       powershell.exe -NoProfile -Command "Test-Path -LiteralPath '$user_scripts\\code-review-graph.exe'" 2>/dev/null | grep -qi true; then
    graphify_exe="$user_scripts\\code-review-graph.exe"
  fi

  if [[ -z "$graphify_exe" ]]; then
    log_warn "code-review-graph.exe not found in Python's Scripts directory after install."
    add_skipped_step \
      "code-review-graph (auto-mode code review indexing)" \
      "code-review-graph installed but code-review-graph.exe not found at expected location" \
      "From Windows PowerShell: $py_cmd -m pip show code-review-graph ; then add the package's Scripts dir to PATH and run: code-review-graph install"
    return 1
  fi

  log_info "Running code-review-graph install (via $graphify_exe)..."
  if ! powershell.exe -NoProfile -Command "& '$graphify_exe' install"; then
    log_warn "Windows code-review-graph install failed."
    add_skipped_step \
      "code-review-graph (auto-mode code review indexing)" \
      "code-review-graph install command failed (code-review-graph was installed but post-install step failed)" \
      "From Windows PowerShell: & '$graphify_exe' install"
    return 1
  fi

  log_info "code-review-graph ready (installed on Windows). Auto-mode runs via SessionStart hook."
  return 0
}

install_code_review_graph() {
  # In WSL+Windows-claude hybrid: install code-review-graph on the WINDOWS side
  # using powershell.exe (WSL interop). The Windows-side claude can then invoke it.
  if is_windows_claude_hybrid; then
    install_code_review_graph_windows_side
    return
  fi

  # Ensure Python is present
  local pip_cmd
  pip_cmd=$(resolve_pip_command)
  if [[ -z "$pip_cmd" ]]; then
    install_python || return
    pip_cmd=$(resolve_pip_command)
    if [[ -z "$pip_cmd" ]]; then
      log_warn "Python installed but pip is not yet on PATH."
      add_skipped_step \
        "code-review-graph (auto-mode code review indexing)" \
        "Python installed but pip not yet on PATH in this shell" \
        "Open a new shell, then re-run setup.sh"
      return
    fi
  fi

  # On macOS (no PEP 668) we can use pip directly. On Linux, PEP 668 blocks
  # system pip — use pipx, which keeps each CLI tool in its own venv.
  log_info "Installing code-review-graph (Tree-sitter code intelligence)..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! "$pip_cmd" install --quiet code-review-graph; then
      log_warn "code-review-graph install failed."
      add_skipped_step \
        "code-review-graph (auto-mode code review indexing)" \
        "pip install code-review-graph failed" \
        "$pip_cmd install code-review-graph && code-review-graph install"
      return
    fi
  else
    if ! ensure_pipx; then
      log_warn "pipx is required on PEP 668 systems but could not be installed."
      add_skipped_step \
        "code-review-graph (auto-mode code review indexing)" \
        "pipx is required on PEP 668 systems and could not be installed" \
        "sudo apt-get install -y pipx && pipx install code-review-graph && code-review-graph install"
      return
    fi
    # Make sure pipx's bin dir is reachable in this shell
    export PATH="$HOME/.local/bin:$PATH"
    if ! pipx install code-review-graph; then
      log_warn "pipx install code-review-graph failed."
      add_skipped_step \
        "code-review-graph (auto-mode code review indexing)" \
        "pipx install code-review-graph failed" \
        "pipx install code-review-graph && code-review-graph install"
      return
    fi
  fi

  if ! code-review-graph install; then
    log_warn "code-review-graph install failed."
    add_skipped_step \
      "code-review-graph (auto-mode code review indexing)" \
      "code-review-graph install command failed" \
      "code-review-graph install"
    return
  fi
  log_info "code-review-graph ready. Auto-mode runs via SessionStart hook (crg-daemon)."
  log_info "Tip: copy templates/code-review-graphignore into each project root for sensible default excludes."
}

verify_installation() {
  local domain="$1"
  # Primary signal: claude plugin install exit codes captured during install
  if [[ ${#INSTALL_FAILURES[@]} -gt 0 ]]; then
    printf '%s\n' "${INSTALL_FAILURES[@]}"
    return
  fi
  # Optional secondary cross-check: if installed_plugins.json exists at the
  # standard path, verify expected entries are present. If it doesn't exist
  # (e.g. WSL+Windows hybrid where claude reads /mnt/c/.../.claude/), trust
  # install exit codes.
  local installed_file="$HOME/.claude/plugins/installed_plugins.json"
  local config_file="$SCRIPT_DIR/plugins.json"
  if [[ ! -f "$installed_file" ]]; then
    return
  fi
  node -e "
const fs = require('fs');
let cfg, installed;
try { cfg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); }
catch (e) { process.exit(0); }
try { installed = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')); }
catch (e) { process.exit(0); }
const domain = process.argv[3];
const expected = []
  .concat(cfg.global || [])
  .concat((cfg.domains && cfg.domains[domain]) || []);
const installedKeys = new Set(Object.keys(installed.plugins || {}));
expected
  .filter(p => p.marketplace)
  .map(p => p.name + '@' + p.marketplace)
  .filter(k => !installedKeys.has(k))
  .forEach(k => process.stdout.write(k + '\n'));
" "$config_file" "$installed_file" "$domain"
}

show_verification_report() {
  local missing="$1"
  local count
  count=$(printf '%s\n' "$missing" | grep -c .)
  echo ""
  echo -e "${RED}======================================================${NC}"
  echo -e "${RED}  SETUP INCOMPLETE${NC}"
  echo -e "${RED}  ${count} plugin(s) did not register in${NC}"
  echo -e "${RED}  ~/.claude/plugins/installed_plugins.json:${NC}"
  echo -e "${RED}======================================================${NC}"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo -e "${RED}  [FAIL] $line${NC}"
  done <<< "$missing"
  echo ""
  echo -e "${YELLOW}  Fix: re-run setup, or install manually:${NC}"
  echo -e "${YELLOW}    claude plugin install <name>@<marketplace> --scope user${NC}"
  echo -e "${RED}======================================================${NC}"
  echo ""
}

run_update() {
  log_info "Updating AI Sherpa core skills..."
  register_marketplaces
  local plugin_list
  plugin_list=$(_read_plugins "global") || { log_error "Cannot read plugins.json — aborting."; exit 1; }
  if [[ -n "$plugin_list" ]]; then
    while IFS='|' read -r type name source; do
      [[ -z "$type" ]] && continue
      claude plugin update "$name" \
        || log_warn "$name update may have failed — re-run --update to retry."
    done <<< "$plugin_list"
  fi
  install_skills
  write_settings
  install_code_review_graph
  log_info "Core skills and settings updated. Project CLAUDE.md was NOT modified."
}

main() {
  local UPDATE_MODE=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --update) UPDATE_MODE=true; shift ;;
      *) log_error "Unknown argument: $1  (valid: --update)"; exit 1 ;;
    esac
  done

  echo -e "${CYAN}  AI Sherpa — Company-wide Claude Code Setup${NC}"

  if is_wsl; then
    log_info "WSL detected (${WSL_DISTRO_NAME:-Windows Subsystem for Linux})."
  fi

  # If WSL is using the Windows-side claude binary, redirect global config writes
  # to the Windows user's home so claude actually sees them.
  if is_windows_claude_hybrid; then
    local win_claude_dir
    win_claude_dir=$(resolve_windows_claude_home)
    if [[ -n "$win_claude_dir" ]]; then
      EFFECTIVE_HOME=$(dirname "$win_claude_dir")
      log_warn "WSL+Windows hybrid detected:"
      log_warn "  claude binary: $(command -v claude)"
      log_warn "  Redirecting global config to: $win_claude_dir"
      log_warn "  (WSL ~/.claude/ would be ignored by the Windows-side claude)"
    fi
  fi

  if [[ "$UPDATE_MODE" == true ]]; then
    run_update
    exit 0
  fi

  # Detect user-level (run from inside the AI Sherpa repo) vs project-level run
  local is_user_level=false
  if [[ -f "$SCRIPT_DIR/core/CLAUDE.md" && "$PWD" == "$SCRIPT_DIR" ]]; then
    is_user_level=true
    log_info "Running from inside AI Sherpa repo — installing at USER level (~/.claude/)."
  fi

  # --- Prerequisites ---
  log_info "Checking prerequisites..."

  if ! check_command node; then
    log_info "Node.js not found. Installing via nvm..."
    # --fail: abort on HTTP error codes (prevents silent 404→bash execution)
    curl --fail -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    if ! check_command nvm; then
      log_error "nvm installed but could not be sourced from $NVM_DIR/nvm.sh"
      log_error "Close this terminal, reopen, and re-run setup.sh"
      exit 1
    fi
    nvm install 20
    nvm use 20
    log_info "Node.js $(node --version) installed via nvm."
  else
    log_info "Node.js $(node --version) found."
  fi

  if ! check_command git; then
    if install_git_via_pkg_manager && check_command git; then
      log_info "Git $(git --version) installed."
    else
      log_error "Git not found and automatic install failed."
      log_error "Install Git manually from https://git-scm.com/ (or via your package manager), then re-run this script."
      exit 1
    fi
  else
    log_info "Git found."
  fi

  if ! check_command claude; then
    log_info "Claude Code not found. Installing..."
    npm install -g @anthropic-ai/claude-code
    log_info "Claude Code installed."
  else
    log_info "Claude Code found."
  fi

  # --- Domain selection ---
  echo ""
  echo "Which domain are you working in?"
  echo "  --- Engineering ---"
  echo "  [1] Embedded Software (C/C++, firmware, RTOS)"
  echo "  [2] Web (full-stack: frontend + backend + UI/UX)"
  echo "  [3] Data Science / ML"
  echo "  [4] DevOps / Platform"
  echo "  --- Business ---"
  echo "  [5] Marketing"
  echo "  [6] Sales"
  echo "  [7] Finance / Accounting"
  echo "  [8] Customer Service / Support"
  echo "  [9] Procurement / Operations"
  echo "  --- AI & UI/UX ---"
  echo "  [10] AI / ML Agents (RAG, evals, prompt engineering)"
  echo "  [11] Frontend + UI/UX"
  echo ""
  read -rp "Enter number [1-11]: " domain_choice

  local domain
  case "$domain_choice" in
    1)  domain="embedded" ;;
    2)  domain="web" ;;
    3)  domain="data" ;;
    4)  domain="devops" ;;
    5)  domain="marketing" ;;
    6)  domain="sales" ;;
    7)  domain="finance" ;;
    8)  domain="service" ;;
    9)  domain="procurement" ;;
    10) domain="ai" ;;
    11) domain="frontend" ;;
    *)  log_error "Invalid choice: $domain_choice. Run the script again."; exit 1 ;;
  esac

  # --- New or existing project (project-level only) ---
  local project_type=""
  if [[ "$is_user_level" != true ]]; then
    echo ""
    echo "New project or existing project?"
    echo "  [1] New project"
    echo "  [2] Existing project (CLAUDE.md will be appended, not replaced)"
    echo ""
    read -rp "Enter number [1-2]: " project_choice
    case "$project_choice" in
      1) project_type="new" ;;
      2) project_type="existing" ;;
      *) log_error "Invalid choice: $project_choice. Run the script again."; exit 1 ;;
    esac
  fi

  # --- Install ---
  register_marketplaces "$domain"
  install_core_skills
  install_domain_skills "$domain"
  install_skills "$domain"
  write_settings
  if [[ "$is_user_level" == true ]]; then
    write_global_claude_md "$domain"
  else
    write_project_settings
    copy_claude_md "$domain" "$project_type"
  fi
  install_code_review_graph

  # --- Embedded-specific: detect Windows toolchains/flashers via powershell.exe ---
  # Even in hybrid mode the user's toolchains live on Windows; calling powershell.exe
  # gives the detection script native registry + Program Files access.
  if [[ "$domain" == "embedded" ]]; then
    local detect_script_unix="$SCRIPT_DIR/scripts/detect-embedded-toolchain.ps1"
    if [[ -f "$detect_script_unix" ]]; then
      if is_windows_claude_hybrid && has_windows_interop; then
        local detect_script_win target_home_win
        detect_script_win=$(wslpath -w "$detect_script_unix")
        target_home_win=$(wslpath -w "$EFFECTIVE_HOME")
        log_info "Detecting embedded toolchain and flashing tools (via powershell.exe)..."
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$detect_script_win" -TargetHome "$target_home_win" \
          || log_warn "Toolchain detection exited non-zero — embedded-toolchain.json may be incomplete."
      else
        log_warn "Skipping toolchain detection: pure-Linux embedded detection not yet implemented."
        add_skipped_step \
          "Embedded toolchain detection (~/.claude/embedded-toolchain.json)" \
          "Only Windows-side detection is implemented; pure-Linux embedded host detected" \
          "Run manually: pwsh -File '$detect_script_unix' -TargetHome '$EFFECTIVE_HOME'   (requires PowerShell + Windows toolchains)"
      fi
    else
      log_warn "Toolchain detection script not found at $detect_script_unix"
    fi
  fi

  # --- WSL-specific caveats ---
  if is_wsl && [[ "$domain" == "web" ]]; then
    add_skipped_step \
      "Claude Code Chrome integration (--chrome / /chrome)" \
      "Not supported on WSL by upstream Claude Code (requires native Chrome/Edge)" \
      "Use Chrome integration from a native Windows shell, or rely on Playwright (already installed) for browser tasks. Docs: https://code.claude.com/docs/en/chrome"
  fi

  # --- Verify ---
  local missing
  missing=$(verify_installation "$domain")
  if [[ -n "$missing" ]]; then
    show_verification_report "$missing"
    show_skipped_steps_report
    print_summary "$domain" "$is_user_level"
    exit 1
  fi
  log_info "All expected plugins verified in installed_plugins.json."
  show_skipped_steps_report
  print_summary "$domain" "$is_user_level"
}

# Source guard — prevents main() running when sourced by tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
