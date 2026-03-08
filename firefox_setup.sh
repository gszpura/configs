#!/usr/bin/env bash
# =============================================================================
# firefox_setup.sh — Automated Firefox configuration via enterprise policies
# =============================================================================
#
# WHAT THIS DOES:
#   Installs Firefox extensions automatically using the Firefox policy engine.
#   Extensions are force-installed on next Firefox launch — no clicking needed.
#
# USAGE:
#   ./firefox_setup.sh          Apply Firefox configuration
#   ./firefox_setup.sh --status Show current policy status
#
# HOW IT WORKS:
#   Firefox reads /etc/firefox/policies/policies.json on startup (works for
#   both deb and snap installs on Ubuntu). Extensions listed as force_installed
#   are downloaded and installed automatically without user prompts.
#
# ADDING EXTENSIONS:
#   Find the extension ID on addons.mozilla.org → the internal ID is shown
#   in the page source or via about:debugging in Firefox.
#   Add an entry to EXTENSIONS below.
#
# Tested on: Ubuntu 24.04 LTS (Firefox deb and snap)
# =============================================================================

set -uo pipefail

POLICY_DIR="/etc/firefox/policies"
POLICY_FILE="${POLICY_DIR}/policies.json"

# =============================================================================
# Extensions to install
# Format: ["extension-id"]="https://addons.mozilla.org/...xpi"
# =============================================================================
declare -A EXTENSIONS=(
    ["treestyletab@piro.sakura.ne.jp"]="https://addons.mozilla.org/firefox/downloads/latest/tree-style-tab/latest.xpi"
    ["uBlock0@raymondhill.net"]="https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
)

declare -A EXTENSION_NAMES=(
    ["treestyletab@piro.sakura.ne.jp"]="Tree Style Tab"
    ["uBlock0@raymondhill.net"]="uBlock Origin"
)

# =============================================================================
# Colors
# =============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

info()   { echo -e "  ${BLUE}i${NC}  $*"; }
ok()     { echo -e "  ${GREEN}✓${NC}  $*"; }
skip()   { echo -e "  ${DIM}●${NC}  $* ${DIM}(already configured)${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail()   { echo -e "  ${RED}✗${NC}  $*"; }
header() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
}

# =============================================================================
# Build the policies.json content from EXTENSIONS
# =============================================================================
build_policy_json() {
    local ext_block=""
    local first=true

    for id in "${!EXTENSIONS[@]}"; do
        local url="${EXTENSIONS[$id]}"
        [[ "$first" == true ]] || ext_block+=","
        ext_block+="
      \"${id}\": {
        \"installation_mode\": \"force_installed\",
        \"install_url\": \"${url}\"
      }"
        first=false
    done

    cat <<EOF
{
  "policies": {
    "ExtensionSettings": {${ext_block}
    }
  }
}
EOF
}

# =============================================================================
# Status: check what's currently in the policy file
# =============================================================================
show_status() {
    header "Firefox Policy Status"

    if [[ ! -f "$POLICY_FILE" ]]; then
        warn "No policy file found at $POLICY_FILE"
        info "Run without --status to create it."
        return
    fi

    ok "Policy file exists: $POLICY_FILE"
    echo ""
    echo -e "${BOLD}Configured extensions:${NC}"

    for id in "${!EXTENSIONS[@]}"; do
        local name="${EXTENSION_NAMES[$id]}"
        if grep -q "$id" "$POLICY_FILE" 2>/dev/null; then
            ok "$name ($id)"
        else
            warn "$name — NOT in policy ($id)"
        fi
    done
}

# =============================================================================
# Apply policy
# =============================================================================
apply_policy() {
    header "Configuring Firefox"

    # Check if Firefox is installed
    if ! command -v firefox &>/dev/null && ! snap list firefox &>/dev/null 2>&1; then
        warn "Firefox does not appear to be installed — applying policy anyway."
        warn "It will take effect when Firefox is installed and launched."
    fi

    # Warn if Firefox is running (policy is read at startup)
    if pgrep -x firefox &>/dev/null; then
        warn "Firefox is currently running."
        warn "Close and reopen Firefox for the policy to take effect."
    fi

    # Create policy directory
    if [[ ! -d "$POLICY_DIR" ]]; then
        info "Creating $POLICY_DIR ..."
        sudo mkdir -p "$POLICY_DIR"
    fi

    # Build desired policy content
    local desired
    desired=$(build_policy_json)

    # Check if already up to date
    if [[ -f "$POLICY_FILE" ]]; then
        local current
        current=$(cat "$POLICY_FILE")
        if [[ "$current" == "$desired" ]]; then
            skip "policies.json is already up to date"
            echo ""
            info "Extensions will be installed on next Firefox launch:"
            for id in "${!EXTENSION_NAMES[@]}"; do
                info "  • ${EXTENSION_NAMES[$id]}"
            done
            return 0
        fi
    fi

    # Write policy file
    echo "$desired" | sudo tee "$POLICY_FILE" > /dev/null
    ok "Written: $POLICY_FILE"

    echo ""
    ok "Extensions queued for installation:"
    for id in "${!EXTENSION_NAMES[@]}"; do
        ok "  • ${EXTENSION_NAMES[$id]}"
    done

    echo ""
    info "Restart Firefox — extensions will install automatically on launch."
}

# =============================================================================
# Main
# =============================================================================
STATUS_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --status) STATUS_ONLY=true ;;
        --help|-h)
            sed -n '/^# USAGE/,/^# HOW/p' "$0" | head -5 | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

if $STATUS_ONLY; then
    show_status
else
    apply_policy
fi
