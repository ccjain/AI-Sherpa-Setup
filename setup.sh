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
  echo "  Update later: ./setup.sh --update"
  echo -e "${CYAN}======================================================${NC}\n"
}

# Source guard — prevents main() running when sourced by tests.
# main() is added in Task 2; this guard is a no-op until then.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  declare -f main &>/dev/null && main "$@" || {
    echo "[AI Sherpa] setup.sh loaded successfully. Run after Task 2 adds main()."
  }
fi
