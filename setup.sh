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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2;37m'; MAGENTA='\033[1;35m'; NC='\033[0m'
log_info()   { echo -e "${GREEN}[AI Sherpa]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[AI Sherpa]${NC} $1"; }
log_error()  { echo -e "${RED}[AI Sherpa]${NC} $1"; }
# Visually-distinct level for "the user must do X themselves before this tool
# works." Plain log_warn is too easy to scroll past during a noisy install;
# action lines get magenta + explicit prefix, AND are collected into
# show_user_actions_report so they're surfaced again at the end of the run.
log_action() { echo -e "${MAGENTA}[ACTION REQUIRED]${NC} $1"; }

print_logo() {
  # Use printf with %s so the body strings (which contain literal backslashes)
  # don't conflict with the ANSI escape sequences in $CYAN / $NC. echo -e
  # was eating the leading backslash of $NC on lines ending in '\'.
  printf '\n'
  printf "${CYAN}%s${NC}\n" '                                                                      /\'
  printf "${CYAN}%s${NC}\n" '   █████╗ ██╗    ███████╗██╗  ██╗███████╗██████╗ ██████╗  █████╗     /  \'
  printf "${CYAN}%s${NC}\n" '  ██╔══██╗██║    ██╔════╝██║  ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗   / /\ \'
  printf "${CYAN}%s${NC}\n" '  ███████║██║    ███████╗███████║█████╗  ██████╔╝██████╔╝███████║  /_/  \_\'
  printf "${CYAN}%s${NC}\n" '  ██╔══██║██║    ╚════██║██╔══██║██╔══╝  ██╔══██╗██╔═══╝ ██╔══██║'
  printf "${CYAN}%s${NC}\n" '  ██║  ██║██║    ███████║██║  ██║███████╗██║  ██║██║     ██║  ██║'
  printf "${CYAN}%s${NC}\n" '  ╚═╝  ╚═╝╚═╝    ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝'
  printf '\n'
  printf "${DIM}%s${NC}\n" "            Guiding your team's Claude Code expedition."
  printf '\n'
}

SKIPPED_STEPS=()
add_skipped_step() {
  # args: name | reason | manual_install
  SKIPPED_STEPS+=("$1|$2|$3")
}

INSTALL_FAILURES=()
add_install_failure() {
  INSTALL_FAILURES+=("$1")
}

# Things the user MUST do themselves before the tool works (open a new shell,
# install a prereq, enable a system feature, run a manual command). These are
# surfaced TWICE: inline via log_action when discovered, and again in
# show_user_actions_report at the end so a noisy install can't bury them.
USER_ACTIONS=()
add_user_action() {
  # args: title | why | command
  USER_ACTIONS+=("$1|$2|$3")
}
show_user_actions_report() {
  if [[ ${#USER_ACTIONS[@]} -eq 0 ]]; then return; fi
  echo ""
  echo -e "${MAGENTA}==========================================================${NC}"
  echo -e "${MAGENTA}  ACTION REQUIRED (${#USER_ACTIONS[@]})${NC}"
  echo -e "${MAGENTA}  Setup is done, but these need YOU before the tool works:${NC}"
  echo -e "${MAGENTA}==========================================================${NC}"
  local i=1
  for entry in "${USER_ACTIONS[@]}"; do
    IFS='|' read -r title why cmd <<< "$entry"
    echo ""
    echo -e "${MAGENTA}  $i. $title${NC}"
    [[ -n "$why" ]] && echo "     Why: $why"
    [[ -n "$cmd" ]] && echo -e "     Run: ${NC}$cmd"
    i=$((i + 1))
  done
  echo ""
  echo -e "${MAGENTA}==========================================================${NC}"
  echo ""
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
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  local domain_md="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$core_md" ]]; then
    log_error "core/CLAUDE.md not found at: $core_md"
    exit 1
  fi
  if [[ ! -f "$domain_md" ]]; then
    log_error "Domain CLAUDE.md not found at: $domain_md"
    exit 1
  fi
  local target="$PWD/CLAUDE.md"
  if [[ "$project_type" == "existing" && -f "$target" ]]; then
    log_warn "Appending AI Sherpa rules to existing CLAUDE.md (original preserved)"
    {
      printf '\n---\n'
      echo "<!-- AI Sherpa core + $domain rules — do not edit below this line -->"
      cat "$core_md"
      printf '\n\n---\n\n'
      cat "$domain_md"
    } >> "$target"
  else
    {
      cat "$core_md"
      printf '\n\n---\n\n'
      cat "$domain_md"
    } > "$target"
  fi
  log_info "Merged core + $domain CLAUDE.md installed at $target"
}

write_ai_sherpa_state() {
  local domain="$1"
  local state_dir="$EFFECTIVE_HOME/.claude"
  mkdir -p "$state_dir"
  local state_file="$state_dir/.ai-sherpa-state.json"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$state_file" <<EOF
{
  "domain":    "$domain",
  "installed": "$now",
  "version":   "1"
}
EOF
  log_info "Recorded domain '$domain' in $state_file (for future --update runs)."
}

get_ai_sherpa_domain() {
  local state_file="$EFFECTIVE_HOME/.claude/.ai-sherpa-state.json"
  [[ ! -f "$state_file" ]] && return 1
  node -e "
try{const c=JSON.parse(require('fs').readFileSync('$state_file','utf8'));if(c.domain)process.stdout.write(c.domain)}catch(e){}" 2>/dev/null
}

write_global_claude_md() {
  local domain="$1"
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  local domain_md="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$core_md" ]]; then
    log_error "core/CLAUDE.md not found at: $core_md"
    exit 1
  fi
  if [[ ! -f "$domain_md" ]]; then
    log_error "Domain CLAUDE.md not found at: $domain_md"
    exit 1
  fi
  local claude_dir="$EFFECTIVE_HOME/.claude"
  local target="$claude_dir/CLAUDE.md"
  mkdir -p "$claude_dir"
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.bak"
    log_warn "Backed up existing $target to $target.bak"
  fi
  # Merge: core (universal) first, then the chosen domain's rules.
  # Universal guidance reads first; domain refines on top.
  {
    cat "$core_md"
    printf '\n\n---\n\n'
    cat "$domain_md"
  } > "$target"
  log_info "Merged core + $domain rules written to $target ($(wc -l < "$target") lines)"
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
# Defensively enable a plugin after install. `claude plugin install` enables by
# default, but a re-install of a previously-disabled plugin can stay disabled.
# Explicit enable is idempotent and guarantees the post-setup state is [ON].
# On enable failure, surface as ACTION REQUIRED so the user sees it in the
# end-of-run summary.
_enable_plugin() {
  local spec="$1"
  if claude plugin enable "$spec" 2>/dev/null; then
    log_info "  [ENABLE] $spec activated"
  else
    log_action "$spec installed but 'claude plugin enable' failed — the plugin may load disabled."
    add_user_action "Activate plugin $spec" \
      "Setup installed the plugin but the explicit 'claude plugin enable' call failed. Without enable, Claude Code may load the plugin in a disabled state and skills/commands from it won't fire." \
      "claude plugin enable $spec"
  fi
}

_install_plugin() {
  local type="$1" name="$2" source="$3"
  if [[ "$type" == "marketplace" ]]; then
    if ! claude plugin install "$name@$source" --scope user; then
      log_warn "$name install failed — see error above."
      add_install_failure "$name@$source"
      return
    fi
    _enable_plugin "$name@$source"
  elif [[ "$type" == "github" ]]; then
    claude plugin marketplace add "https://github.com/$source" 2>/dev/null || true
    if ! claude plugin install "$name" --scope user; then
      log_warn "$name install failed — see error above."
      add_install_failure "$name"
      return
    fi
    _enable_plugin "$name"
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

  // Map declared marketplaces by name -> repo
  const declared = new Map();
  (config.marketplaces || []).forEach(m => {
    const repo = typeof m === 'string' ? m : (m.repo || '');
    const name = typeof m === 'string' ? '' : (m.name || '');
    if (name && repo) declared.set(name, repo);
  });

  // Output one line per referenced marketplace: 'repo|name'.
  // Declared ones include the repo so we can 'marketplace add' them.
  // Builtins shipped with Claude Code (e.g. claude-plugins-official) have an
  // empty repo — we only run 'marketplace update' to populate their cache,
  // which is empty on a fresh install and causes 'plugin not found in
  // marketplace' errors for the official plugins.
  needed.forEach(name => {
    const repo = declared.get(name) || '';
    process.stdout.write(repo + '|' + name + '\n');
  });
});
" < "$config_file")
  if [[ -z "$entries" ]]; then return; fi
  while IFS='|' read -r repo name; do
    [[ -z "$name" ]] && continue
    if [[ -n "$repo" ]]; then
      log_info "Registering marketplace: $repo"
      claude plugin marketplace add "$repo" 2>/dev/null || true
    else
      log_info "Updating builtin marketplace: $name"
    fi
    claude plugin marketplace update "$name" 2>/dev/null \
      || log_warn "Could not update marketplace $name — $name plugins may fail to install."
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

install_pypi_tool_windows_side() {
  # args: name | package | postInstall | upgrade(true/false)
  local name="$1" package="$2" post_install="$3" upgrade="${4:-false}"
  local exe_name="${package}.exe"
  local pip_flag=""
  [[ "$upgrade" == "true" ]] && pip_flag="--upgrade"

  if ! has_windows_interop; then
    log_warn "Windows interop (powershell.exe) not available from this WSL distro."
    add_skipped_step \
      "$name (PyPI tool, WSL+Windows hybrid)" \
      "Hybrid mode requires Windows interop, which is disabled in this WSL distro" \
      "From Windows PowerShell: winget install Python.Python.3.12 ; py -m pip install $package${post_install:+ ; $post_install}"
    return 1
  fi

  log_info "Installing $name on Windows (via powershell.exe from WSL)..."

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
      add_skipped_step "$name (PyPI tool, WSL+Windows hybrid)" \
        "Windows Python may be installed but pip is not reachable" \
        "From Windows PowerShell: py -m pip install $package${post_install:+ ; $post_install}"
      return 1
    fi
  fi

  log_info "Installing $name on Windows (using: $pip_cmd${pip_flag:+ $pip_flag})..."
  if ! powershell.exe -NoProfile -Command "$pip_cmd install --quiet $pip_flag $package"; then
    add_skipped_step "$name (PyPI tool, WSL+Windows hybrid)" "Windows pip install $package failed" \
      "From Windows PowerShell: $pip_cmd install $package${post_install:+ ; $post_install}"
    return 1
  fi

  # Resolve Python's Scripts dirs once — needed for both the post-install
  # lookup AND for adding the dir(s) to Windows User PATH so future shells
  # (especially Claude SessionStart hooks) can find the installed exe.
  local py_cmd="py"
  case "$pip_cmd" in
    "py -m pip")     py_cmd="py" ;;
    "python -m pip") py_cmd="python" ;;
    "pip")           py_cmd="python" ;;
  esac

  local sys_scripts user_scripts
  sys_scripts=$(powershell.exe -NoProfile -Command "$py_cmd -c \"import sysconfig; print(sysconfig.get_path('scripts'))\"" 2>/dev/null | tr -d '\r\n')
  user_scripts=$(powershell.exe -NoProfile -Command "$py_cmd -c \"import site, os; print(os.path.join(site.getuserbase(), 'Scripts'))\"" 2>/dev/null | tr -d '\r\n')

  # Persist Scripts dirs to Windows User PATH (winget Python doesn't add them
  # automatically — this is why crg-daemon isn't reachable from a fresh shell
  # after install).
  local s
  for s in "$sys_scripts" "$user_scripts"; do
    [[ -z "$s" ]] && continue
    local already
    already=$(powershell.exe -NoProfile -Command "([Environment]::GetEnvironmentVariable('PATH','User') -split ';') -contains '$s'" 2>/dev/null | tr -d '\r\n')
    if [[ "$already" != "True" ]]; then
      log_info "Adding '$s' to Windows User PATH..."
      powershell.exe -NoProfile -Command "[Environment]::SetEnvironmentVariable('PATH', ([Environment]::GetEnvironmentVariable('PATH','User').TrimEnd(';') + ';$s'), 'User')" 2>/dev/null || true
    fi
  done

  if [[ -n "$post_install" ]]; then
    local tool_exe=""

    if [[ -n "$sys_scripts" ]] && \
       powershell.exe -NoProfile -Command "Test-Path -LiteralPath '$sys_scripts\\$exe_name'" 2>/dev/null | grep -qi true; then
      tool_exe="$sys_scripts\\$exe_name"
    elif [[ -n "$user_scripts" ]] && \
         powershell.exe -NoProfile -Command "Test-Path -LiteralPath '$user_scripts\\$exe_name'" 2>/dev/null | grep -qi true; then
      tool_exe="$user_scripts\\$exe_name"
    fi

    if [[ -z "$tool_exe" ]]; then
      add_skipped_step "$name (PyPI tool, WSL+Windows hybrid)" \
        "$exe_name not found in Python's Scripts directory after install" \
        "From Windows PowerShell: $py_cmd -m pip show $package ; then add Scripts dir to PATH and run: $post_install"
      return 1
    fi

    # The post-install command will start with the package name (e.g.
    # `code-review-graph install` -> rewrite to use the absolute exe path).
    local rewritten_post="${post_install/$package/&\\\"$tool_exe\\\"}"
    # Fallback: just run the absolute exe with whatever args follow the package name
    local post_args="${post_install#$package}"
    log_info "Running $name post-install (via $tool_exe)..."
    if ! powershell.exe -NoProfile -Command "& '$tool_exe' $post_args"; then
      add_skipped_step "$name (PyPI tool, WSL+Windows hybrid)" \
        "Post-install command failed: $post_install" \
        "From Windows PowerShell: & '$tool_exe' $post_args"
      return 1
    fi
  fi

  log_info "$name ready (installed on Windows)."
  return 0
}

install_pypi_tool() {
  # args: name | package | postInstall | upgrade(true/false)
  local name="$1" package="$2" post_install="$3" upgrade="${4:-false}"

  if is_windows_claude_hybrid; then
    install_pypi_tool_windows_side "$name" "$package" "$post_install" "$upgrade"
    return
  fi

  local pip_cmd
  pip_cmd=$(resolve_pip_command)
  if [[ -z "$pip_cmd" ]]; then
    install_python || return
    pip_cmd=$(resolve_pip_command)
    if [[ -z "$pip_cmd" ]]; then
      log_warn "Python installed but pip is not yet on PATH."
      add_skipped_step "$name (PyPI tool)" "Python installed but pip not yet on PATH" \
        "Open a new shell, then re-run setup.sh"
      return
    fi
  fi

  local upgrade_flag=""
  [[ "$upgrade" == "true" ]] && upgrade_flag="--upgrade"

  # Cascade across available installers in preference order: uv tool (isolated,
  # fast) -> pipx (isolated, mature; auto-installed on Linux via ensure_pipx)
  # -> bare pip (shares global env, warned). When one fails mid-install (e.g.
  # uv hitting ERROR_OPEN_FAILED on Windows long-path wheels), fall through to
  # the next instead of skipping the step entirely.
  local install_ok=false
  local last_err=""

  if ! $install_ok && check_command uv; then
    local uv_action="install"
    [[ "$upgrade" == "true" ]] && uv_action="upgrade"
    log_info "Installing $name (uv tool $uv_action)..."
    if uv tool "$uv_action" "$package"; then
      export PATH="$HOME/.local/bin:$PATH"
      install_ok=true
    else
      last_err="uv tool $uv_action failed"
      log_warn "$name uv tool $uv_action failed - retrying with next installer..."
    fi
  fi

  if ! $install_ok; then
    local have_pipx=false
    if check_command pipx; then
      have_pipx=true
    elif [[ "$OSTYPE" != "darwin"* ]]; then
      # On Linux ensure_pipx will auto-install pipx if missing (PEP 668-safe path).
      ensure_pipx && have_pipx=true
    fi
    if $have_pipx; then
      export PATH="$HOME/.local/bin:$PATH"
      local pipx_action="install"
      if [[ "$upgrade" == "true" ]] && pipx list 2>/dev/null | grep -q "package $package "; then
        pipx_action="upgrade"
      fi
      log_info "Installing $name (pipx $pipx_action)..."
      if pipx "$pipx_action" "$package"; then
        install_ok=true
      else
        last_err="pipx $pipx_action failed"
        log_warn "$name pipx $pipx_action failed - retrying with next installer..."
      fi
    fi
  fi

  if ! $install_ok; then
    log_warn "$name will install into the global Python env ($pip_cmd). For isolation, install 'uv' (https://docs.astral.sh/uv/) or 'pipx' first and re-run."
    log_info "Installing $name (pip${upgrade_flag:+ $upgrade_flag})..."
    if "$pip_cmd" install --quiet $upgrade_flag "$package"; then
      install_ok=true
    else
      last_err="pip install failed"
    fi
  fi

  if ! $install_ok; then
    add_skipped_step "$name (PyPI tool)" "All installers failed (last: $last_err)" \
      "Try one of: uv tool install $package  /  pipx install $package  /  $pip_cmd install --user $package${post_install:+ ; $post_install}"
    return
  fi

  if [[ -n "$post_install" ]]; then
    # Verify the post-install command's leading token (the binary the package
    # just installed) is on PATH before invoking. If a fallback installer dumped
    # the binary into a dir not yet on PATH, defer with a clear remediation
    # rather than crashing the whole setup with "command not found".
    local post_first
    post_first=$(echo "$post_install" | awk '{print $1}')
    if [[ -n "$post_first" ]] && ! check_command "$post_first"; then
      log_action "$name installed but '$post_first' isn't on PATH in this shell yet - deferring post-install."
      add_user_action "Finish $name setup" \
        "$name was installed but the binary's directory isn't on PATH in this shell - the post-install step couldn't run. After a fresh shell opens with the updated PATH, this one command finishes wiring it up." \
        "Open a new shell, then run: $post_install"
      log_info "$name installed (post-install deferred - see ACTION REQUIRED at end of setup)."
      return
    fi
    if ! eval "$post_install"; then
      add_skipped_step "$name (PyPI tool)" "Post-install '$post_install' failed" "$post_install"
      return
    fi
  fi
  log_info "$name ready."
}

install_rust() {
  # cargo may exist on disk but the current shell's PATH hasn't picked it up
  # yet — common right after a fresh rustup install, or in any shell opened
  # before rustup ran. Surface ~/.cargo/bin to this process before deciding
  # to reinstall, so we don't redundantly re-run the installer.
  if ! check_command cargo && [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    log_info "Found cargo at ~/.cargo/bin/cargo; adding to PATH for this run."
    export PATH="$HOME/.cargo/bin:$PATH"
  fi

  if check_command cargo; then
    # cargo is present but may be from an outdated toolchain. Several crates
    # we install (rtk uses str.floor_char_boundary, stabilized in Rust 1.80)
    # fail to compile on old stable channels with "unstable library feature"
    # errors. If rustup is available, refresh the stable channel.
    if check_command rustup; then
      log_info "Updating Rust toolchain (rustup update stable)..."
      rustup update stable 2>/dev/null \
        || log_warn "rustup update stable failed; if a later cargo install errors with 'unstable library feature', update manually."
    else
      log_warn "cargo found but rustup not on PATH; cannot auto-update Rust. If a cargo install later fails with 'unstable library feature', install rustup from https://rustup.rs and re-run."
    fi
    return 0
  fi
  log_info "Rust toolchain not found. Installing..."
  local rc=1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if check_command brew; then brew install rust; rc=$?
    else
      curl --fail --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
      rc=$?
    fi
  elif check_command apt-get; then
    sudo apt-get update -qq && sudo apt-get install -y rustc cargo; rc=$?
  elif check_command dnf; then
    sudo dnf install -y rust cargo; rc=$?
  else
    # Fallback: rustup-init
    curl --fail --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    log_warn "Automatic Rust install failed (rc=$rc)."
    return 1
  fi

  # Make rustup-installed cargo reachable in this shell
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  export PATH="$HOME/.cargo/bin:$PATH"

  if check_command cargo; then
    log_info "Rust installed. $(cargo --version)"
    return 0
  fi
  log_warn "Rust installed but cargo not yet on PATH. Open a new shell, then re-run setup.sh."
  return 1
}

install_cargo_tool() {
  # args: name | git | package | upgrade(true/false)
  local name="$1" git="$2" package="$3" upgrade="${4:-false}"
  if ! check_command cargo; then
    if ! install_rust; then
      add_skipped_step "$name (Rust / cargo tool)" "Rust toolchain not installed" \
        "Install Rust from https://rustup.rs, then: cargo install${git:+ --git $git}${package:+ $package}"
      return
    fi
  fi
  local upgrade_flag=""
  [[ "$upgrade" == "true" ]] && upgrade_flag="--force"
  log_info "Installing $name (cargo${upgrade_flag:+ $upgrade_flag})..."
  local args=("install")
  [[ -n "$upgrade_flag" ]] && args+=("$upgrade_flag")
  if [[ -n "$git" ]]; then args+=(--git "$git"); else args+=("$package"); fi
  if ! cargo "${args[@]}"; then
    add_skipped_step "$name (Rust / cargo tool)" "cargo install failed" \
      "cargo install${upgrade_flag:+ --force}${git:+ --git $git}${package:+ $package}"
    return
  fi
  log_info "$name ready."
}

install_git_clone_tool() {
  # args: name | repo | destination | postInstall
  local name="$1" repo="$2" destination="$3" post_install="$4"
  if ! check_command git; then
    add_skipped_step "$name (git-clone tool)" "git not installed" "Install git, then re-run setup."
    return
  fi
  local dest="${destination/#~/$HOME}"
  local parent
  parent=$(dirname "$dest")
  [[ -n "$parent" && ! -d "$parent" ]] && mkdir -p "$parent"
  if [[ -d "$dest/.git" ]]; then
    log_info "$name already at $dest — pulling latest..."
    (cd "$dest" && git pull --quiet) || log_warn "git pull failed for $name"
  else
    log_info "Cloning $name from $repo to $dest..."
    if ! git clone --quiet "https://github.com/$repo" "$dest"; then
      add_skipped_step "$name (git-clone tool)" "git clone https://github.com/$repo failed" \
        "git clone https://github.com/$repo $dest"
      return
    fi
  fi
  if [[ -n "$post_install" ]]; then
    (cd "$dest" && eval "$post_install") || log_warn "$name post-install failed"
  fi
  log_info "$name ready at $dest."
}

# Read plugins.json tools.<global|domain> entries and dispatch by source.
# upgrade=true => pip --upgrade / cargo --force / git pull (already does)
install_tools() {
  local domain="${1:-}" upgrade="${2:-false}"
  local config_file="$SCRIPT_DIR/plugins.json"
  [[ -f "$config_file" ]] || return 0
  local entries
  entries=$(node -e "
let raw='';process.stdin.setEncoding('utf8');
process.stdin.on('data',d=>raw+=d);
process.stdin.on('end',()=>{
  let c;try{c=JSON.parse(raw)}catch(e){process.exit(0)}
  const d='$domain';const t=c.tools||{};
  const es=[].concat(t.global||[]).concat((d&&t[d])||[]);
  es.forEach(e=>{
    const src=e.source||'';
    process.stdout.write([
      src,
      e.name||'',
      e.package||'',
      e.git||'',
      e.repo||'',
      e.destination||'',
      e.postInstall||''
    ].join('\t')+'\n');
  });
});
" < "$config_file")
  [[ -z "$entries" ]] && return 0

  while IFS=$'\t' read -r source name package git repo destination post_install; do
    [[ -z "$source" ]] && continue
    case "$source" in
      pypi)      install_pypi_tool "$name" "$package" "$post_install" "$upgrade" ;;
      cargo)     install_cargo_tool "$name" "$git" "$package" "$upgrade" ;;
      git-clone) install_git_clone_tool "$name" "$repo" "$destination" "$post_install" ;;
      *)         log_warn "Unknown tool source '$source' for $name; skipping." ;;
    esac
  done <<< "$entries"
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
  log_info "Updating AI Sherpa..."

  # Recall which domain was picked at install time (state file written by
  # write_ai_sherpa_state). If not present, fall back to global-only refresh.
  local saved_domain
  saved_domain=$(get_ai_sherpa_domain)
  if [[ -n "$saved_domain" ]]; then
    log_info "Recalled domain '$saved_domain' from previous install."
  else
    log_warn "No saved domain found. Updating global plugins/skills/tools only."
    log_warn "Re-run bash setup.sh (not --update) once to pick a domain and record state."
  fi

  # Refresh marketplace caches for the marketplaces this domain actually uses
  register_marketplaces "$saved_domain"

  # Update global plugins always
  local plugin_list
  plugin_list=$(_read_plugins "global") || { log_error "Cannot read plugins.json — aborting."; exit 1; }
  if [[ -n "$plugin_list" ]]; then
    while IFS='|' read -r type name source; do
      [[ -z "$type" ]] && continue
      log_info "Updating $name..."
      claude plugin update "$name" \
        || log_warn "$name update may have failed — re-run --update to retry."
    done <<< "$plugin_list"
  fi

  # Update plugins for the saved domain too
  if [[ -n "$saved_domain" ]]; then
    local domain_plugins
    domain_plugins=$(_read_plugins "$saved_domain") || true
    if [[ -n "$domain_plugins" ]]; then
      while IFS='|' read -r type name source; do
        [[ -z "$type" ]] && continue
        log_info "Updating $name ($saved_domain)..."
        claude plugin update "$name" \
          || log_warn "$name update may have failed — re-run --update to retry."
      done <<< "$domain_plugins"
    fi
  fi

  # Re-clone raw skills (clone overwrites)
  install_skills "$saved_domain"

  # Upgrade tools: pip --upgrade / cargo --force / git pull
  install_tools "$saved_domain" "true"

  write_settings
  log_info "Update complete. Plugins, skills, and tools refreshed to latest${saved_domain:+ for domain '$saved_domain'}."
  log_info "Project CLAUDE.md was NOT modified."
}

run_uninstall() {
  echo ""
  echo -e "${YELLOW}======================================================${NC}"
  echo -e "${YELLOW}  AI Sherpa -- UNINSTALL${NC}"
  echo -e "${YELLOW}======================================================${NC}"
  echo ""
  echo "This will remove from $EFFECTIVE_HOME/.claude/:"
  echo "  - All Claude plugins listed in plugins.json (global + every domain)"
  echo "  - All raw skills cloned from plugins.json skills.* repos"
  echo "  - All CLI tools listed in plugins.json tools.*"
  echo "  - The marketplaces registered by setup"
  echo "  - settings.json and CLAUDE.md (restored from .bak if present, else deleted)"
  echo ""
  echo "  NOT touched: Node.js / Python / Rust / Git toolchains, your projects,"
  echo "  manually-installed plugins, ~/.claude/projects/ session logs."
  echo ""
  read -rp "Type 'uninstall' to confirm: " confirm
  if [[ "$confirm" != "uninstall" ]]; then
    log_info "Aborted (confirmation not received)."
    return
  fi

  local config_file="$SCRIPT_DIR/plugins.json"
  [[ ! -f "$config_file" ]] && { log_warn "plugins.json not found, nothing to uninstall."; return; }

  # 1. Uninstall Claude plugins
  log_info "Removing Claude plugins..."
  node -e "
const fs=require('fs');
try{
  const c=JSON.parse(fs.readFileSync('$config_file','utf8'));
  const all=[].concat(c.global||[]);
  if(c.domains){for(const d of Object.keys(c.domains)){all.push(...(c.domains[d]||[]))}}
  all.forEach(p=>{if(p.marketplace)process.stdout.write(p.name+'@'+p.marketplace+'\n')});
}catch(e){}" | while read -r entry; do
    [[ -z "$entry" ]] && continue
    log_info "  - $entry"
    claude plugin uninstall "$entry" --scope user 2>/dev/null || true
  done

  # 2. Uninstall CLI tools
  log_info "Removing CLI tools..."
  node -e "
const fs=require('fs');
try{
  const c=JSON.parse(fs.readFileSync('$config_file','utf8'));
  const t=c.tools||{};
  const all=[].concat(t.global||[]);
  for(const d of Object.keys(t)){if(d==='global')continue;all.push(...(t[d]||[]))}
  all.forEach(x=>process.stdout.write([x.source||'',x.name||'',x.package||'',x.destination||''].join('\t')+'\n'));
}catch(e){}" | while IFS=$'\t' read -r source name package destination; do
    [[ -z "$source" ]] && continue
    case "$source" in
      pypi)
        log_info "  - $name (pip uninstall)"
        local pip_cmd
        pip_cmd=$(resolve_pip_command)
        if [[ -n "$pip_cmd" && -n "$package" ]]; then
          if check_command pipx; then pipx uninstall "$package" 2>/dev/null || true; fi
          "$pip_cmd" uninstall -y "$package" 2>/dev/null || true
        fi
        ;;
      cargo)
        local pkg="${package:-$name}"
        log_info "  - $name (cargo uninstall $pkg)"
        check_command cargo && cargo uninstall "$pkg" 2>/dev/null || true
        ;;
      git-clone)
        local dest="${destination/#\~/$HOME}"
        if [[ -n "$dest" && -d "$dest" ]]; then
          log_info "  - $name (rm $dest)"
          rm -rf "$dest"
        fi
        ;;
    esac
  done

  # 3. Remove raw skills
  log_info "Removing raw skills from $EFFECTIVE_HOME/.claude/skills/..."
  local skills_dir="$EFFECTIVE_HOME/.claude/skills"
  node -e "
const fs=require('fs');
try{
  const c=JSON.parse(fs.readFileSync('$config_file','utf8'));
  const s=c.skills||{};
  const all=[].concat(s.global||[]);
  for(const d of Object.keys(s)){if(d==='global')continue;all.push(...(s[d]||[]))}
  all.forEach(x=>process.stdout.write([x.repo||'',x.subpath||'skills'].join('\t')+'\n'));
}catch(e){}" | while IFS=$'\t' read -r repo subpath; do
    [[ -z "$repo" ]] && continue
    local slug; slug=$(echo "$repo" | tr '/' '-')
    local tmp; tmp=$(mktemp -d -t "ai-sherpa-uninst-${slug}.XXXXXX")
    if git clone --depth 1 --quiet "https://github.com/$repo" "$tmp" 2>/dev/null; then
      if [[ -d "$tmp/$subpath" ]]; then
        for entry in "$tmp/$subpath"/*/; do
          local n
          n=$(basename "$entry")
          if [[ -d "$skills_dir/$n" ]]; then
            log_info "  - $n"
            rm -rf "$skills_dir/$n"
          fi
        done
      fi
    fi
    rm -rf "$tmp"
  done

  # 4. Remove AI Sherpa state file (the saved-domain marker)
  local state_file="$EFFECTIVE_HOME/.claude/.ai-sherpa-state.json"
  if [[ -f "$state_file" ]]; then
    log_info "Removing AI Sherpa state file..."
    rm -f "$state_file"
  fi

  # 5. Restore settings.json + CLAUDE.md from .bak (or delete)
  log_info "Restoring settings + rules..."
  local settings_file="$EFFECTIVE_HOME/.claude/settings.json"
  local claude_md="$EFFECTIVE_HOME/.claude/CLAUDE.md"
  if [[ -f "${settings_file}.bak" ]]; then
    mv "${settings_file}.bak" "$settings_file"
    log_info "  Restored $settings_file from .bak"
  elif [[ -f "$settings_file" ]]; then
    rm -f "$settings_file"
    log_info "  Removed $settings_file (no .bak)"
  fi
  if [[ -f "${claude_md}.bak" ]]; then
    mv "${claude_md}.bak" "$claude_md"
    log_info "  Restored $claude_md from .bak"
  elif [[ -f "$claude_md" ]]; then
    rm -f "$claude_md"
    log_info "  Removed $claude_md (no .bak)"
  fi

  # 5. Remove marketplaces
  log_info "Removing registered marketplaces..."
  node -e "
const fs=require('fs');
try{
  const c=JSON.parse(fs.readFileSync('$config_file','utf8'));
  (c.marketplaces||[]).forEach(m=>{if(m.name)process.stdout.write(m.name+'\n')});
}catch(e){}" | while read -r mp; do
    [[ -z "$mp" ]] && continue
    log_info "  - $mp"
    claude plugin marketplace remove "$mp" 2>/dev/null || true
  done

  echo ""
  echo -e "${GREEN}======================================================${NC}"
  echo -e "${GREEN}  AI Sherpa Uninstall Complete${NC}"
  echo -e "${GREEN}======================================================${NC}"
  echo "  Toolchains (Node / Python / Rust / Git) were NOT removed."
  echo "  Re-run bash setup.sh to start fresh."
  echo -e "${GREEN}======================================================${NC}"
  echo ""
}

main() {
  local UPDATE_MODE=false
  local UNINSTALL_MODE=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --update)    UPDATE_MODE=true; shift ;;
      --uninstall) UNINSTALL_MODE=true; shift ;;
      *) log_error "Unknown argument: $1  (valid: --update, --uninstall)"; exit 1 ;;
    esac
  done

  print_logo

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

  if [[ "$UNINSTALL_MODE" == true ]]; then
    run_uninstall
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
  install_tools "$domain"
  write_ai_sherpa_state "$domain"

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
    show_user_actions_report
    print_summary "$domain" "$is_user_level"
    exit 1
  fi
  log_info "All expected plugins verified in installed_plugins.json."
  show_skipped_steps_report
  show_user_actions_report
  print_summary "$domain" "$is_user_level"
}

# Source guard — prevents main() running when sourced by tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
