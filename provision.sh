#!/usr/bin/env bash
# =============================================================================
# provision.sh — Idempotent system provisioning script
# =============================================================================
#
# USAGE:
#   ./provision.sh              Full provisioning (install everything)
#   ./provision.sh --status     Show what is/isn't installed, no changes made
#   ./provision.sh --help       Show this help
#
# PREREQUISITES:
#   1. Install git:   sudo apt install git
#   2. Configure git: git config --global user.name "Your Name"
#                     git config --global user.email "you@example.com"
#   3. Add your SSH public key to GitHub/GitLab
#   4. Clone this repo: git clone git@github.com:gszpura/configs.git ~/src/configs
#   5. Run this script: cd ~/src/configs && bash provision.sh
#
# TOOLS LIST:
#   Edit tools.list to add/remove/modify tools to install.
#   Supported types: apt, snap, github, url, script, manual
#
# IDEMPOTENCY:
#   Safe to run multiple times. Already-installed tools are detected and skipped.
#   If the script is interrupted, just re-run it — it will pick up where it left off.
#
# Tested on: Ubuntu 24.04 LTS
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_FILE="${SCRIPT_DIR}/tools.list"
LOG_FILE="/tmp/provision_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# Terminal colors & formatting
# =============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# =============================================================================
# Output helpers
# =============================================================================
log_raw()  { echo "$*" >> "$LOG_FILE"; }
info()     { echo -e "  ${BLUE}i${NC}  $*"; log_raw "[INFO]  $*"; }
ok()       { echo -e "  ${GREEN}✓${NC}  $*"; log_raw "[OK]    $*"; }
skip()     { echo -e "  ${DIM}●${NC}  $* ${DIM}(already installed)${NC}"; log_raw "[SKIP]  $*"; }
warn()     { echo -e "  ${YELLOW}⚠${NC}  $*"; log_raw "[WARN]  $*"; }
fail()     { echo -e "  ${RED}✗${NC}  $*"; log_raw "[FAIL]  $*"; }
manual()   { echo -e "  ${YELLOW}☞${NC}  $*"; log_raw "[MANUAL] $*"; }

step() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ $*${NC}"
    log_raw ""
    log_raw "=== STEP: $* ==="
}

header() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    log_raw ""
    log_raw "====== $* ======"
}

# =============================================================================
# State tracking
# =============================================================================
declare -A TOOL_STATUS   # name → installed | skipped | failed | manual | missing
declare -a MANUAL_STEPS  # list of manual step descriptions
declare -a FAILED_TOOLS  # list of failed tool names

STATUS_ONLY=false

# =============================================================================
# Option parsing helpers
# =============================================================================

# get_option <options_string> <key>
# Extracts the value for 'key:' from a semicolon-separated options string.
# Returns 0 and prints value if found; returns 1 if not found.
#
# Example: get_option "dir:~/.zsh/foo;env:RUNZSH=no" "dir"  →  ~/.zsh/foo
get_option() {
    local options="$1"
    local key="$2"
    local opt
    while IFS=';' read -ra opts; do
        for opt in "${opts[@]}"; do
            opt="${opt#"${opt%%[![:space:]]*}"}"  # ltrim
            if [[ "$opt" == "$key:"* ]]; then
                echo "${opt#$key:}"
                return 0
            fi
        done
    done <<< "$options"
    return 1
}

# Expand leading tilde to $HOME
expand_path() {
    echo "${1/#\~/$HOME}"
}

# =============================================================================
# Check functions (is a tool already installed?)
# =============================================================================

# Returns 0 if the apt package is installed, 1 otherwise
apt_installed() {
    dpkg -s "$1" &>/dev/null 2>&1
}

# Returns 0 if the snap package is installed, 1 otherwise
snap_installed() {
    snap list "$1" &>/dev/null 2>&1
}

# Main check dispatcher. Returns 0 = already installed, 1 = needs installing.
check_installed() {
    local type="$1"
    local name="$2"
    local source="$3"
    local check="$4"
    local options="$5"

    # --- Use explicit check override if provided ---
    if [[ "$check" != "-" && -n "$check" ]]; then
        if [[ "$check" == path:* ]]; then
            local path
            path=$(expand_path "${check#path:}")
            [[ -e "$path" ]]
            return $?
        elif [[ "$check" == cmd:* ]]; then
            eval "${check#cmd:}" &>/dev/null 2>&1
            return $?
        fi
    fi

    # --- Default check per type ---
    case "$type" in
        apt)
            apt_installed "$source"
            ;;
        snap)
            snap_installed "$name"
            ;;
        github)
            local dir
            if dir=$(get_option "$options" "dir"); then
                dir=$(expand_path "$dir")
            else
                dir="$HOME/${source##*/}"
            fi
            [[ -d "$dir" ]]
            ;;
        url)
            local save
            if save=$(get_option "$options" "save"); then
                save=$(expand_path "$save")
                [[ -f "$save" ]]
            else
                return 1
            fi
            ;;
        script)
            # Scripts have side effects everywhere; always require a path: or cmd: check
            return 1
            ;;
        manual)
            # Always display manual steps
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Install functions
# =============================================================================

# Run a command, capturing output. On failure, show the last lines.
run_logged() {
    local tmp
    tmp=$(mktemp)
    if "$@" >>"$tmp" 2>&1; then
        cat "$tmp" >> "$LOG_FILE"
        rm -f "$tmp"
        return 0
    else
        local code=$?
        cat "$tmp" >> "$LOG_FILE"
        tail -8 "$tmp" | sed 's/^/      /' >&2
        rm -f "$tmp"
        return $code
    fi
}

install_apt() {
    local source="$1"
    local options="$2"
    local extra_args
    extra_args=$(get_option "$options" "args") || extra_args=""
    # shellcheck disable=SC2086
    run_logged sudo apt-get install -y $extra_args "$source"
}

install_snap() {
    local name="$1"
    local options="$2"
    local extra_args
    extra_args=$(get_option "$options" "args") || extra_args=""
    # shellcheck disable=SC2086
    run_logged sudo snap install $extra_args "$name"
}

install_github() {
    local source="$1"   # user/repo
    local options="$2"
    local dir
    if dir=$(get_option "$options" "dir"); then
        dir=$(expand_path "$dir")
    else
        dir="$HOME/${source##*/}"
    fi
    local branch
    branch=$(get_option "$options" "branch") || branch=""

    mkdir -p "$(dirname "$dir")"
    if [[ -n "$branch" ]]; then
        run_logged git clone --depth=1 -b "$branch" "https://github.com/${source}.git" "$dir"
    else
        run_logged git clone --depth=1 "https://github.com/${source}.git" "$dir"
    fi
}

install_url() {
    local source="$1"
    local options="$2"
    local save
    if save=$(get_option "$options" "save"); then
        save=$(expand_path "$save")
    else
        save="/tmp/$(basename "$source")"
    fi

    mkdir -p "$(dirname "$save")"
    info "Downloading to $save ..."
    run_logged curl -fsSL "$source" -o "$save"

    # If extract option present, unzip to the target directory
    local extract
    if extract=$(get_option "$options" "extract"); then
        extract=$(expand_path "$extract")
        mkdir -p "$extract"
        info "Extracting to $extract ..."
        run_logged unzip -o "$save" -d "$extract"
        # Rebuild font cache if this looks like a fonts directory
        if [[ "$extract" == *fonts* ]]; then
            info "Rebuilding font cache ..."
            run_logged fc-cache -fv "$extract" || true
        fi
    fi
}

install_script() {
    local source="$1"
    local options="$2"

    # Build env var prefix (e.g. "env:RUNZSH=no CHSH=no")
    local env_prefix=""
    local env_val
    if env_val=$(get_option "$options" "env"); then
        env_prefix="$env_val"
    fi

    local extra_args
    extra_args=$(get_option "$options" "args") || extra_args=""

    info "Downloading and running install script from $source ..."
    local script_content
    script_content=$(curl -fsSL "$source") || {
        echo "Failed to download install script from $source" >&2
        return 1
    }

    local tmp
    tmp=$(mktemp --suffix=.sh)
    echo "$script_content" > "$tmp"
    chmod +x "$tmp"

    local tmp_log
    tmp_log=$(mktemp)

    # Run with env prefix; script output goes to log; errors to stderr
    # shellcheck disable=SC2086
    if env $env_prefix bash "$tmp" $extra_args >>"$tmp_log" 2>&1; then
        cat "$tmp_log" >> "$LOG_FILE"
        rm -f "$tmp" "$tmp_log"
        return 0
    else
        local code=$?
        cat "$tmp_log" >> "$LOG_FILE"
        tail -10 "$tmp_log" | sed 's/^/      /' >&2
        rm -f "$tmp" "$tmp_log"
        return $code
    fi
}

# =============================================================================
# Core tool processor
# =============================================================================

TOOL_NUMBER=0

process_tool() {
    local type="$1"
    local name="$2"
    local source="$3"
    local check="$4"
    local description="$5"
    local depends="$6"
    local options="$7"

    TOOL_NUMBER=$((TOOL_NUMBER + 1))
    local prefix="[${TOOL_NUMBER}] ${name}"

    # --- Handle manual steps ---
    if [[ "$type" == "manual" ]]; then
        manual "${prefix}: ${description}"
        if [[ "$source" != "-" ]]; then
            manual "        → $source"
        fi
        TOOL_STATUS["$name"]="manual"
        if [[ "$source" != "-" ]]; then
            MANUAL_STEPS+=("${description}  ($source)")
        else
            MANUAL_STEPS+=("${description}")
        fi
        return 0
    fi

    # --- Check dependencies first ---
    if [[ -n "$depends" ]]; then
        IFS=',' read -ra dep_list <<< "$depends"
        for dep in "${dep_list[@]}"; do
            dep="${dep#"${dep%%[![:space:]]*}"}"  # ltrim whitespace
            dep="${dep%"${dep##*[![:space:]]}"}"  # rtrim whitespace
            local dep_status="${TOOL_STATUS[$dep]:-unknown}"
            if [[ "$dep_status" == "failed" || "$dep_status" == "missing" ]]; then
                fail "${prefix} — SKIPPED (dependency '${dep}' failed or missing)"
                TOOL_STATUS["$name"]="failed"
                FAILED_TOOLS+=("$name (dep '$dep' failed)")
                return 0
            fi
        done
    fi

    # --- Check if already installed ---
    if check_installed "$type" "$name" "$source" "$check" "$options"; then
        skip "${prefix}: ${description}"
        TOOL_STATUS["$name"]="installed"
        return 0
    fi

    # --- Status-only mode: just report missing ---
    if $STATUS_ONLY; then
        warn "${prefix}: NOT INSTALLED — ${description}"
        TOOL_STATUS["$name"]="missing"
        return 0
    fi

    # --- Install ---
    info "${prefix}: Installing — ${description}"
    local exit_code=0

    case "$type" in
        apt)    install_apt    "$source" "$options" || exit_code=$? ;;
        snap)   install_snap   "$name"   "$options" || exit_code=$? ;;
        github) install_github "$source" "$options" || exit_code=$? ;;
        url)    install_url    "$source" "$options" || exit_code=$? ;;
        script) install_script "$source" "$options" || exit_code=$? ;;
        *)
            fail "${prefix}: Unknown type '${type}'"
            TOOL_STATUS["$name"]="failed"
            FAILED_TOOLS+=("$name (unknown type)")
            return 0
            ;;
    esac

    if [[ $exit_code -eq 0 ]]; then
        # Run optional post-install command
        local post_cmd
        if post_cmd=$(get_option "$options" "post"); then
            info "${prefix}: Running post-install: $post_cmd"
            if run_logged bash -c "$post_cmd"; then
                ok "${prefix}: Post-install completed"
            else
                warn "${prefix}: Post-install command failed (tool still marked installed)"
            fi
        fi
        ok "${prefix}: Installed successfully"
        TOOL_STATUS["$name"]="installed"
    else
        fail "${prefix}: FAILED (exit code: ${exit_code})"
        warn "  See full output in: ${LOG_FILE}"
        TOOL_STATUS["$name"]="failed"
        FAILED_TOOLS+=("$name")
    fi
}

# =============================================================================
# Parse and process tools.list
# =============================================================================
process_all_tools() {
    step "Processing tools from $(basename "$TOOLS_FILE")"

    if [[ ! -f "$TOOLS_FILE" ]]; then
        fail "tools.list not found at: $TOOLS_FILE"
        exit 1
    fi

    local line_num=0
    while IFS='|' read -r type name source check description depends options; do
        line_num=$((line_num + 1))

        # Skip comment lines and empty lines
        type="${type#"${type%%[![:space:]]*}"}"   # ltrim
        type="${type%"${type##*[![:space:]]}"}"   # rtrim
        [[ -z "$type" || "$type" == \#* ]] && continue

        # Trim all fields
        name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
        source="${source#"${source%%[![:space:]]*}"}"; source="${source%"${source##*[![:space:]]}"}"
        check="${check#"${check%%[![:space:]]*}"}"; check="${check%"${check##*[![:space:]]}"}"
        description="${description#"${description%%[![:space:]]*}"}"; description="${description%"${description##*[![:space:]]}"}"
        depends="${depends#"${depends%%[![:space:]]*}"}"; depends="${depends%"${depends##*[![:space:]]}"}"
        options="${options#"${options%%[![:space:]]*}"}"; options="${options%"${options##*[![:space:]]}"}"

        # Default check to "-" if empty
        [[ -z "$check" ]] && check="-"

        process_tool "$type" "$name" "$source" "$check" "$description" "$depends" "$options"
    done < "$TOOLS_FILE"
}

# =============================================================================
# Post-install configuration steps
# =============================================================================

setup_git_config() {
    step "Git configuration"

    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        skip "Git already configured: ${git_name} <${git_email}>"
        return 0
    fi

    info "Git user info not set. Prompting for input..."

    if [[ -z "$git_name" ]]; then
        read -rp "  Your name for git commits: " git_name
        git config --global user.name "$git_name"
    fi
    if [[ -z "$git_email" ]]; then
        read -rp "  Your email for git commits: " git_email
        git config --global user.email "$git_email"
    fi
    ok "Git configured: ${git_name} <${git_email}>"
}

setup_configs() {
    step "Copying configuration files"

    # --- zshrc ---
    # oh-my-zsh creates a generic ~/.zshrc; we overwrite it with our custom one.
    # Detection: our zshrc sources ~/antigen.zsh on line 1.
    if grep -q "source ~/antigen.zsh" ~/.zshrc 2>/dev/null; then
        skip "~/.zshrc already contains custom configuration"
    else
        cp "${SCRIPT_DIR}/conf_files/zshrc" ~/.zshrc
        ok "Copied conf_files/zshrc → ~/.zshrc"
    fi

    # --- xbindkeys config ---
    if [[ -f ~/.xbindkeysrc ]]; then
        skip "~/.xbindkeysrc already exists"
    else
        cp "${SCRIPT_DIR}/conf_files/xbindkeysrc" ~/.xbindkeysrc
        ok "Copied conf_files/xbindkeysrc → ~/.xbindkeysrc"
    fi

    # --- PyCharm desktop entry ---
    local desktop_dir="${HOME}/.local/share/applications"
    mkdir -p "$desktop_dir"
    if [[ -f "${desktop_dir}/pycharm.desktop" ]]; then
        skip "pycharm.desktop already in ~/.local/share/applications/"
    else
        cp "${SCRIPT_DIR}/conf_files/pycharm.desktop" "${desktop_dir}/"
        ok "Copied conf_files/pycharm.desktop → ${desktop_dir}/"
    fi
}

setup_default_shell() {
    step "Setting default shell to zsh"

    local zsh_path
    zsh_path=$(which zsh 2>/dev/null || echo "")

    if [[ -z "$zsh_path" ]]; then
        fail "zsh not found in PATH — cannot set as default shell"
        return 1
    fi

    local current_shell
    current_shell=$(getent passwd "$USER" | cut -d: -f7)

    if [[ "$current_shell" == "$zsh_path" ]]; then
        skip "Default shell is already zsh ($zsh_path)"
    else
        info "Changing default shell to $zsh_path for user $USER ..."
        chsh -s "$zsh_path"
        ok "Default shell set to $zsh_path (takes effect on next login)"
    fi
}

setup_tilix() {
    step "Configuring Tilix"

    if ! command -v tilix &>/dev/null; then
        warn "Tilix not installed — skipping"
        return 0
    fi

    # Set as default terminal emulator via gsettings (GNOME on Ubuntu 24)
    local current_term
    current_term=$(gsettings get org.gnome.desktop.default-applications.terminal exec 2>/dev/null | tr -d "'")
    if [[ "$current_term" == "tilix" ]]; then
        skip "Tilix is already the default terminal"
    else
        gsettings set org.gnome.desktop.default-applications.terminal exec 'tilix'
        gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'
        ok "Tilix set as default terminal"
    fi

    # Enable dark mode
    local current_theme
    current_theme=$(dconf read /com/gexperts/Tilix/theme-variant 2>/dev/null | tr -d "'")
    if [[ "$current_theme" == "dark" ]]; then
        skip "Tilix dark mode already enabled"
    else
        dconf write /com/gexperts/Tilix/theme-variant "'dark'"
        ok "Tilix dark mode enabled"
    fi
}

setup_xbindkeys() {
    step "Starting xbindkeys"

    if ! which xbindkeys &>/dev/null; then
        warn "xbindkeys not installed — skipping"
        return 0
    fi

    # Only start in a graphical environment
    if [[ -z "${DISPLAY:-}" ]]; then
        warn "No DISPLAY set — skipping xbindkeys start (run manually after login)"
        return 0
    fi

    if pgrep -x xbindkeys &>/dev/null; then
        info "Restarting xbindkeys to pick up new config ..."
        killall xbindkeys 2>/dev/null || true
    fi

    xbindkeys &
    ok "xbindkeys started (PID: $!)"
}

# =============================================================================
# Final summary
# =============================================================================
print_summary() {
    header "Provisioning Summary"

    local n_ok=0 n_fail=0 n_manual=0 n_missing=0

    echo ""
    echo -e "${BOLD}Tool Status:${NC}"
    for name in "${!TOOL_STATUS[@]}"; do
        local status="${TOOL_STATUS[$name]}"
        case "$status" in
            installed) ok    "$name"; n_ok=$((n_ok + 1)) ;;
            failed)    fail  "$name"; n_fail=$((n_fail + 1)) ;;
            manual)    manual "$name (manual step required)"; n_manual=$((n_manual + 1)) ;;
            missing)   warn  "$name (not installed)"; n_missing=$((n_missing + 1)) ;;
        esac
    done

    echo ""
    echo -e "${BOLD}Counts:${NC}"
    [[ $n_ok      -gt 0 ]] && echo -e "  ${GREEN}✓${NC} Installed/present : $n_ok"
    [[ $n_fail    -gt 0 ]] && echo -e "  ${RED}✗${NC} Failed            : $n_fail"
    [[ $n_manual  -gt 0 ]] && echo -e "  ${YELLOW}☞${NC} Manual steps      : $n_manual"
    [[ $n_missing -gt 0 ]] && echo -e "  ${YELLOW}⚠${NC} Not installed     : $n_missing"

    if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${BOLD}${YELLOW}Manual Steps Required:${NC}"
        for step_text in "${MANUAL_STEPS[@]}"; do
            echo -e "  ${YELLOW}→${NC} $step_text"
        done
    fi

    if [[ ${#FAILED_TOOLS[@]:-0} -gt 0 ]]; then
        echo ""
        echo -e "${BOLD}${RED}Failed Tools:${NC}"
        for t in "${FAILED_TOOLS[@]+"${FAILED_TOOLS[@]}"}"; do
            echo -e "  ${RED}✗${NC} $t"
        done
        echo ""
        warn "Re-run this script to retry failed tools."
        warn "Full log: $LOG_FILE"
    fi

    if $STATUS_ONLY && [[ $n_missing -gt 0 ]]; then
        echo ""
        info "Run without --status to install missing tools."
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    # --- Parse arguments ---
    for arg in "$@"; do
        case "$arg" in
            --status)
                STATUS_ONLY=true
                ;;
            --help | -h)
                sed -n '/^# USAGE/,/^# Tested on/p' "$0" | sed 's/^# \?//'
                exit 0
                ;;
            *)
                echo "Unknown argument: $arg"
                echo "Run with --help for usage."
                exit 1
                ;;
        esac
    done

    # --- Header ---
    header "System Provisioning — $(date '+%Y-%m-%d %H:%M:%S')"
    info "Script:  $0"
    info "User:    $USER"
    info "Log:     $LOG_FILE"
    if $STATUS_ONLY; then
        info "Mode:    STATUS ONLY (no changes will be made)"
    else
        info "Mode:    FULL PROVISIONING"
    fi

    # --- Check we're on a Debian/Ubuntu system ---
    if ! command -v apt-get &>/dev/null; then
        fail "apt-get not found. This script requires a Debian/Ubuntu-based system."
        exit 1
    fi

    # --- One-time apt update (skip in status mode) ---
    if ! $STATUS_ONLY; then
        step "Updating apt package lists"
        info "Running apt-get update ..."
        if run_logged sudo apt-get update; then
            ok "Package lists updated"
        else
            warn "apt-get update failed — continuing anyway (cached lists may be used)"
        fi
    fi

    # --- Git configuration (interactive if needed) ---
    if ! $STATUS_ONLY; then
        setup_git_config
    fi

    # --- Process all tools ---
    process_all_tools

    # --- Post-install config steps ---
    if ! $STATUS_ONLY; then
        setup_configs
        setup_default_shell
        setup_tilix
        setup_xbindkeys
    fi

    # --- Summary ---
    print_summary

    if ! $STATUS_ONLY; then
        echo ""
        ok "Provisioning complete."
        info "Log saved to: $LOG_FILE"
        info "Start a new shell session to use zsh: exec zsh"
        echo ""
        echo -e "${YELLOW}Troubleshooting tips:${NC}"
        echo "  • autojump not working?  → apt-cache show autojump"
        echo "  • fzf not working?       → apt-cache show fzf"
        echo "  • bat command?           → on Ubuntu, the binary is 'batcat' (not 'bat')"
        echo "  • alien theme broken?    → make sure FiraCode Nerd Font is set in your terminal"
        echo "  • virtualenvwrapper?     → source ~/.local/bin/virtualenvwrapper.sh"
    fi
}

main "$@"
