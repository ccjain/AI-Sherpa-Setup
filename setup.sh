#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[AI Sherpa]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[AI Sherpa]${NC} $1"; }
log_error() { echo -e "${RED}[AI Sherpa]${NC} $1"; }

check_command() { command -v "$1" &>/dev/null; }

write_settings() {
  local settings_dir="$HOME/.claude"
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

install_core_skills() {
  log_info "Installing core skills (this may take 1-2 minutes)..."
  npx skillsadd obra/superpowers
  npx skillsadd safishamsi/graphify
  npx skillsadd mattpocock/skills
  npx skillsadd pbakaus/impeccable
  npx skillsadd sentry/dev
  log_info "Core skills installed."
}

install_domain_skills() {
  local domain="$1"
  case "$domain" in
    web)
      log_info "Installing web/frontend skills..."
      npx skillsadd anthropics/skills
      npx skillsadd vercel-labs/agent-skills
      npx skillsadd vercel-labs/next-skills
      npx skillsadd vercel-labs/agent-browser
      npx skillsadd shadcn/ui
      ;;
    devops)
      log_info "Installing DevOps skills..."
      npx skillsadd microsoft/azure-skills
      ;;
    embedded|backend|data)
      log_info "No additional skills for $domain — core skills + CLAUDE.md rules apply."
      ;;
  esac
}

print_summary() {
  local domain="$1"
  echo -e "\n${CYAN}======================================================${NC}"
  echo -e "${CYAN}  AI Sherpa Setup Complete${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo "  Domain:   $domain"
  echo "  Settings: $HOME/.claude/settings.json  (secrets protection active)"
  echo "  Settings: $PWD/.claude/settings.json   (project-level)"
  echo "  Rules:    CLAUDE.md installed in $PWD"
  echo ""
  echo "  Next steps:"
  echo "  1. Start Claude Code:   claude"
  echo "  2. Index your codebase: /graphify   (run inside Claude Code)"
  echo "  3. Start coding — AI Sherpa rules are active automatically"
  echo ""
  echo "  Update later: bash \"$SCRIPT_DIR/setup.sh\" --update"
  echo -e "${CYAN}======================================================${NC}\n"
}

run_update() {
  log_info "Updating AI Sherpa core skills..."
  npx skillsadd obra/superpowers
  npx skillsadd safishamsi/graphify
  npx skillsadd mattpocock/skills
  npx skillsadd pbakaus/impeccable
  npx skillsadd sentry/dev
  write_settings
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

  if [[ "$UPDATE_MODE" == true ]]; then
    run_update
    exit 0
  fi

  # Guard: warn if run from inside the ai-sherpa repo itself
  if [[ -f "$PWD/core/CLAUDE.md" && "$PWD" == "$SCRIPT_DIR" ]]; then
    log_warn "You are running setup from inside the AI Sherpa repo."
    log_warn "Please cd to your project directory first, then run:"
    log_warn "  bash $SCRIPT_DIR/setup.sh"
    exit 1
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
    log_error "Git not found. Install from https://git-scm.com/ then re-run this script."
    exit 1
  fi
  log_info "Git found."

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
  echo "  [1] Embedded Software (C/C++, firmware, RTOS)"
  echo "  [2] Web / Frontend (React, Vue, Angular, HTML/CSS)"
  echo "  [3] Backend (Node.js, Python)"
  echo "  [4] Data Science / ML"
  echo "  [5] DevOps / Platform"
  echo ""
  read -rp "Enter number [1-5]: " domain_choice

  local domain
  case "$domain_choice" in
    1) domain="embedded" ;;
    2) domain="web" ;;
    3) domain="backend" ;;
    4) domain="data" ;;
    5) domain="devops" ;;
    *) log_error "Invalid choice: $domain_choice. Run the script again."; exit 1 ;;
  esac

  # --- New or existing project ---
  echo ""
  echo "New project or existing project?"
  echo "  [1] New project"
  echo "  [2] Existing project (CLAUDE.md will be appended, not replaced)"
  echo ""
  read -rp "Enter number [1-2]: " project_choice

  local project_type
  case "$project_choice" in
    1) project_type="new" ;;
    2) project_type="existing" ;;
    *) log_error "Invalid choice: $project_choice. Run the script again."; exit 1 ;;
  esac

  # --- Install ---
  install_core_skills
  install_domain_skills "$domain"
  write_settings
  write_project_settings
  copy_claude_md "$domain" "$project_type"
  print_summary "$domain"
}

# Source guard — prevents main() running when sourced by tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
