#!/bin/bash
# create-config.sh - Generate settings.conf from template
# This script creates a local settings.conf from the example template.
# The generated settings.conf is gitignored and safe for secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXAMPLE_FILE="${PROJECT_ROOT}/config/settings.conf.example"
OUTPUT_FILE="${PROJECT_ROOT}/settings.conf"

# Colors
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if example exists
if [[ ! -f "${EXAMPLE_FILE}" ]]; then
    log_error "Example file not found: ${EXAMPLE_FILE}"
    exit 1
fi

# Check if output already exists
if [[ -f "${OUTPUT_FILE}" ]]; then
    echo -e "${YELLOW}settings.conf already exists.${NC}"
    read -rp "Overwrite? [y/N] " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Keeping existing settings.conf"; exit 0; }
fi

log_info "Creating settings.conf from template..."

# Copy example to output
cp "${EXAMPLE_FILE}" "${OUTPUT_FILE}"

# Secure permissions
chmod 600 "${OUTPUT_FILE}"

log_success "Created ${OUTPUT_FILE} with secure permissions (600)"
log_info "Edit settings.conf to configure your installation:"
log_info "  nano ${OUTPUT_FILE}"
log_info ""
log_info "Key settings to configure:"
log_info "  PI_USER=piadmin              # System username"
log_info "  PI_PASSWORD=                 # Leave empty for random generation"
log_info "  PI_SSH_KEYS=                 # Your SSH public key(s)"
log_info "  SSH_PORT=2222                # Change from default 22"
log_info "  TELEGRAM_ADMIN_TOKEN=        # From @BotFather"
log_info "  TELEGRAM_ADMIN_CHAT_ID=      # Your user ID from @userinfobot"
log_info "  TAILSCALE_AUTH_KEY=          # Optional: for unattended setup"
log_info ""
log_warn "IMPORTANT: settings.conf contains secrets and is gitignored."
log_warn "NEVER commit it to git!"

# Show next steps
echo
log_info "After editing, run the installer:"
log_info "  sudo ./install.sh          # Interactive (with mode selection)"
log_info "  sudo ./install.sh --tui    # Experimental TUI mode"
log_info "  sudo ./install.sh -y       # Non-interactive (requires complete config)"
log_info "  sudo ./install.sh --dry-run # Validate config only"