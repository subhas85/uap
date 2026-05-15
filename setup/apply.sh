#!/usr/bin/env bash
#
# apply.sh — render UAP templates from ~/uap.local/identity.yaml and deploy.
#
# Usage:
#   apply.sh                  # apply every component in identity.components_enabled
#   apply.sh plymouth i3      # apply only the named components
#   apply.sh --dry-run                  # render + show what would change; install nothing
#   apply.sh --no-sudo                  # skip steps that need root
#   apply.sh --force-claude-settings    # overwrite existing ~/.claude/settings.json (claude-settings component only)
#
# See ~/uap/setup/DESIGN.md for the contract.
#
set -euo pipefail

# --- Config / paths -------------------------------------------------------

UAP_DIR="${UAP_DIR:-$HOME/uap}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/uap.local}"
IDENTITY="$LOCAL_DIR/identity.yaml"
RENDER_DIR="$LOCAL_DIR/rendered"
SCHEMA_VERSION=1

DRY_RUN=0
NO_SUDO=0
FORCE_CLAUDE_SETTINGS=0
COMPONENTS_REQUESTED=()

# --- Helpers --------------------------------------------------------------

log()  { printf '\033[1;36m[apply.sh]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[apply.sh]\033[0m WARN: %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[apply.sh]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

run_sudo() {
    if [ "$NO_SUDO" = 1 ]; then
        log "[--no-sudo] would run: sudo $*"
    else
        sudo "$@"
    fi
}

# apt_install — install only the missing packages from the list. Runs
# `apt-get update` exactly once per apply.sh invocation (lazy).
APT_UPDATED=0
apt_install() {
    local pkgs=("$@") missing=()
    local pkg
    for pkg in "${pkgs[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    [ "${#missing[@]}" -eq 0 ] && return 0

    if [ "$APT_UPDATED" = 0 ]; then
        log "apt-get update (once per run)..."
        run_sudo apt-get update -qq
        APT_UPDATED=1
    fi
    log "apt installing: ${missing[*]}"
    run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# Download + install JetBrains Mono Nerd Font (the patched variant) into
# the operator's ~/.local/share/fonts/. The apt package `fonts-jetbrains-mono`
# is the regular (non-patched) font; the Nerd Font ships separately on GitHub.
install_jetbrains_nerd_font() {
    if fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd'; then
        log "fonts: JetBrainsMono Nerd Font already installed"
        return 0
    fi
    log "fonts: downloading JetBrainsMono Nerd Font from GitHub releases"
    local dest="$HOME_DIR/.local/share/fonts/JetBrainsMono"
    install -d "$dest"
    local tmpzip
    tmpzip=$(mktemp --suffix=.zip)
    curl -fsSL -o "$tmpzip" \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    apt_install unzip
    unzip -oq "$tmpzip" -d "$dest"
    rm -f "$tmpzip"
    fc-cache -f "$dest" >/dev/null
    log "fonts: JetBrainsMono Nerd Font installed to $dest"
}

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)                DRY_RUN=1;                shift ;;
        --no-sudo)                NO_SUDO=1;                shift ;;
        --force-claude-settings)  FORCE_CLAUDE_SETTINGS=1;  shift ;;
        -h|--help)                sed -n '3,12p' "$0";      exit 0 ;;
        --*)        die "unknown flag: $1" ;;
        *)          COMPONENTS_REQUESTED+=("$1"); shift ;;
    esac
done

# --- Prereqs --------------------------------------------------------------

need envsubst
need yq
[ -f "$IDENTITY" ] || die "no identity file at $IDENTITY. Run the wizard first."

# Validate schema version
file_schema=$(yq '.schema_version' "$IDENTITY")
[ "$file_schema" = "$SCHEMA_VERSION" ] \
    || die "identity.yaml schema_version is '$file_schema', apply.sh expects '$SCHEMA_VERSION'."

# --- Export identity values as env vars for envsubst ---------------------

export OS_NAME OS_NAME_LOWER TAGLINE HOSTNAME HOME_DIR
export USERNAME OPERATOR_EMAIL OPERATOR_ROLE
export PALETTE FONT_NAME FONT_SIZE
export BG_HEX BG_ALT_HEX BG_R BG_G BG_B
export FG_HEX FG_DIM_HEX
export ACCENT_HEX URGENT_HEX GREEN_HEX YELLOW_HEX PURPLE_HEX CYAN_HEX
export BORDER_HEX INACTIVE_HEX
export MOD_KEY WORKSPACE_COUNT GTK_THEME
export WORKSPACE_HUB_NAME PERMISSION_MODE
export RDP_LCID SESMAN_POLICY INSTALL_RECONNECTWM
export SUBWORKSPACES_BLOCK

OS_NAME=$(yq         '.os.name'              "$IDENTITY")
OS_NAME_LOWER=$(yq   '.os.name_lower'        "$IDENTITY")
TAGLINE=$(yq         '.os.tagline'           "$IDENTITY")
HOSTNAME=$(yq        '.os.hostname'          "$IDENTITY")

USERNAME=$(yq        '.operator.username'    "$IDENTITY")
OPERATOR_EMAIL=$(yq  '.operator.email'       "$IDENTITY")
OPERATOR_ROLE=$(yq   '.operator.role'        "$IDENTITY")
HOME_DIR="/home/${USERNAME}"

PALETTE=$(yq         '.theme.palette'        "$IDENTITY")
FONT_NAME=$(yq       '.theme.font'           "$IDENTITY")
FONT_SIZE=$(yq       '.theme.font_size'      "$IDENTITY")
BG_HEX=$(yq          '.theme.bg_hex'         "$IDENTITY")
BG_ALT_HEX=$(yq      '.theme.bg_alt_hex'     "$IDENTITY")
BG_R=$(yq            '.theme.bg_r'           "$IDENTITY")
BG_G=$(yq            '.theme.bg_g'           "$IDENTITY")
BG_B=$(yq            '.theme.bg_b'           "$IDENTITY")
FG_HEX=$(yq          '.theme.fg_hex'         "$IDENTITY")
FG_DIM_HEX=$(yq      '.theme.fg_dim_hex'     "$IDENTITY")
ACCENT_HEX=$(yq      '.theme.accent_hex'     "$IDENTITY")
URGENT_HEX=$(yq      '.theme.urgent_hex'     "$IDENTITY")
GREEN_HEX=$(yq       '.theme.green_hex'      "$IDENTITY")
YELLOW_HEX=$(yq      '.theme.yellow_hex'     "$IDENTITY")
PURPLE_HEX=$(yq      '.theme.purple_hex'     "$IDENTITY")
CYAN_HEX=$(yq        '.theme.cyan_hex'       "$IDENTITY")
BORDER_HEX=$(yq      '.theme.border_hex'     "$IDENTITY")
INACTIVE_HEX=$(yq    '.theme.inactive_hex'   "$IDENTITY")

MOD_KEY=$(yq           '.wm.mod_key'                  "$IDENTITY")
WORKSPACE_COUNT=$(yq   '.wm.workspace_count'          "$IDENTITY")
GTK_THEME=$(yq         '.theme.gtk_theme'             "$IDENTITY")

WORKSPACE_HUB_NAME=$(yq '.ai.workspace_hub_name'      "$IDENTITY")
PERMISSION_MODE=$(yq    '.ai.permission_mode'         "$IDENTITY")

RDP_LCID=$(yq             '.locale.rdp_lcid'             "$IDENTITY")
SESMAN_POLICY=$(yq        '.xrdp.sesman_policy'          "$IDENTITY")
INSTALL_RECONNECTWM=$(yq  '.xrdp.install_reconnectwm'    "$IDENTITY")

# Generate the subworkspace markdown block from identity.ai.subworkspaces[]
SUBWORKSPACES_BLOCK=$(
    while IFS= read -r ws; do
        [ -z "$ws" ] && continue
        printf "  %-9s → ~/%s\n" "${ws}/" "${ws}"
    done < <(yq '.ai.subworkspaces[]' "$IDENTITY")
)

# Allow-list of variables that envsubst will substitute. Anything else (literal $foo, $PATH, etc.) is left alone.
TEMPLATE_VARS='${OS_NAME} ${OS_NAME_LOWER} ${TAGLINE} ${HOSTNAME} ${HOME_DIR} ${USERNAME} ${OPERATOR_EMAIL} ${OPERATOR_ROLE} ${FONT_NAME} ${FONT_SIZE} ${BG_HEX} ${BG_ALT_HEX} ${BG_R} ${BG_G} ${BG_B} ${FG_HEX} ${FG_DIM_HEX} ${ACCENT_HEX} ${URGENT_HEX} ${GREEN_HEX} ${YELLOW_HEX} ${PURPLE_HEX} ${CYAN_HEX} ${BORDER_HEX} ${INACTIVE_HEX} ${MOD_KEY} ${WORKSPACE_COUNT} ${WORKSPACE_HUB_NAME} ${PERMISSION_MODE} ${RDP_LCID} ${GTK_THEME} ${SUBWORKSPACES_BLOCK}'

# --- Generic render: walk configs/<component>/, produce rendered/<component>/

# Resolve a component name to its source directory. Components live under one
# of the top-level scopes: os/, ai/, workflows/.  Search in that order.
component_source_dir() {
    local component="$1"
    for scope in os ai workflows; do
        if [ -d "$UAP_DIR/$scope/$component" ]; then
            printf '%s' "$UAP_DIR/$scope/$component"
            return 0
        fi
    done
    return 1
}

render_component() {
    local component="$1"
    local src
    src=$(component_source_dir "$component") || die "component '$component': not found under uap/{os,ai,workflows}/"
    local dst="$RENDER_DIR/$component"
    mkdir -p "$dst"

    while IFS= read -r -d '' file; do
        local rel="${file#"$src"/}"
        if [[ "$rel" == *.tmpl ]]; then
            local out_rel="${rel%.tmpl}"
            # Rename theme-named files so they match OS_NAME_LOWER
            out_rel="${out_rel//uap./${OS_NAME_LOWER}.}"
            mkdir -p "$(dirname "$dst/$out_rel")"
            envsubst "$TEMPLATE_VARS" < "$file" > "$dst/$out_rel"
        else
            mkdir -p "$(dirname "$dst/$rel")"
            cp -f "$file" "$dst/$rel"
        fi
    done < <(find "$src" -type f -print0)

    # If identity provides an asset override (e.g. assets.logo for plymouth), use it.
    if [ "$component" = "plymouth" ]; then
        local logo_rel
        logo_rel=$(yq '.assets.logo // ""' "$IDENTITY")
        if [ -n "$logo_rel" ] && [ -f "$LOCAL_DIR/$logo_rel" ]; then
            cp -f "$LOCAL_DIR/$logo_rel" "$dst/logo.png"
        fi
    fi

    log "$component: rendered into $dst"
}

# --- Component install hooks ---------------------------------------------

install_workspace_hub() {
    local render="$RENDER_DIR/workspace-hub"
    local hub="$HOME_DIR/$WORKSPACE_HUB_NAME"

    if [ "$DRY_RUN" = 1 ]; then
        log "workspace-hub: DRY-RUN — would install CLAUDE.md + subworkspace symlinks at $hub"
        return 0
    fi

    install -d "$hub"

    # Symlink each declared subworkspace from ~/<name> into the hub
    while IFS= read -r ws; do
        [ -z "$ws" ] && continue
        if [ -d "$HOME_DIR/$ws" ]; then
            ln -sfn "$HOME_DIR/$ws" "$hub/$ws"
        else
            warn "workspace-hub: ~/$ws not found — symlink skipped"
        fi
    done < <(yq '.ai.subworkspaces[]' "$IDENTITY")

    install -m 644 "$render/CLAUDE.md" "$hub/CLAUDE.md"
    log "workspace-hub: installed CLAUDE.md + symlinks at $hub"
}

install_i3() {
    local render="$RENDER_DIR/i3"
    local target="$HOME_DIR/.config/i3"

    if [ "$DRY_RUN" = 1 ]; then
        log "i3: DRY-RUN — would apt install i3 i3-wm i3status i3lock xdotool"
        log "i3: DRY-RUN — would install JetBrains Mono Nerd Font if missing"
        log "i3: DRY-RUN — would install $target/config + $target/i3status.conf (no i3-msg reload)"
        return 0
    fi

    apt_install i3 i3-wm i3status i3lock xdotool fonts-jetbrains-mono
    install_jetbrains_nerd_font

    install -d "$target"
    install -m 644 "$render/i3-config"      "$target/config"
    install -m 644 "$render/i3status.conf"  "$target/i3status.conf"

    # Live reload (safe — preserves session/windows)
    DISPLAY="${DISPLAY:-:10}" i3-msg reload >/dev/null 2>&1 || true
    log "i3: installed config + i3status.conf, sent reload"
}

install_typora_themes() {
    local render="$RENDER_DIR/typora-themes"
    local target="$HOME_DIR/.config/Typora/themes"

    if [ "$DRY_RUN" = 1 ]; then
        log "typora-themes: DRY-RUN — would copy rendered themes to $target/"
        return 0
    fi

    install -d "$target"
    cp -r "$render"/* "$target/"
    log "typora-themes: copied themes to $target/"
}

install_workspace_title_daemon() {
    local render="$RENDER_DIR/workspace-title-daemon"

    if [ "$DRY_RUN" = 1 ]; then
        log "workspace-title-daemon: DRY-RUN — would install $HOME_DIR/.local/bin/i3-workspace-title"
        return 0
    fi

    install -d "$HOME_DIR/.local/bin"
    install -m 755 "$render/i3-workspace-title" "$HOME_DIR/.local/bin/i3-workspace-title"
    log "workspace-title-daemon: installed ${HOME_DIR}/.local/bin/i3-workspace-title (i3 will exec_always launch it)"
}

install_desktop_entries() {
    local render="$RENDER_DIR/desktop-entries"

    if [ "$DRY_RUN" = 1 ]; then
        log "desktop-entries: DRY-RUN — would install claude-workspace.desktop + claude.png under $HOME_DIR/.local/share/{applications,icons/claude}/ and pre-seed rofi drun cache"
        return 0
    fi

    install -d "$HOME_DIR/.local/share/applications" "$HOME_DIR/.local/share/icons/claude"

    install -m 644 "$render/claude-workspace.desktop" \
        "$HOME_DIR/.local/share/applications/claude-workspace.desktop"
    install -m 644 "$render/claude.png" \
        "$HOME_DIR/.local/share/icons/claude/claude.png"

    update-desktop-database "$HOME_DIR/.local/share/applications" 2>/dev/null || true

    # Pre-seed rofi drun cache to keep Claude at top until usage history accumulates
    local cache="$HOME_DIR/.cache/rofi3.druncache"
    if [ -f "$cache" ] && ! grep -q 'claude-workspace.desktop' "$cache"; then
        echo "20 claude-workspace.desktop" | cat - "$cache" > "$cache.new" && mv "$cache.new" "$cache"
        log "desktop-entries: pre-seeded rofi cache"
    fi

    log "desktop-entries: installed Claude launcher + icon"
}

install_xrdp() {
    local render="$RENDER_DIR/xrdp"

    if [ "$DRY_RUN" = 1 ]; then
        log "xrdp: DRY-RUN — would apt install xrdp xorgxrdp"
        log "xrdp: DRY-RUN — would patch /etc/xrdp/sesman.ini Policy to ${SESMAN_POLICY}"
        [ "$INSTALL_RECONNECTWM" = "true" ] && log "xrdp: DRY-RUN — would install /etc/xrdp/reconnectwm.sh"
        if [ -n "$RDP_LCID" ] && [ "$RDP_LCID" != "0x00000409" ]; then
            local lcid_lower="${RDP_LCID#0x}"
            lcid_lower="${lcid_lower,,}"
            log "xrdp: DRY-RUN — would mirror /etc/xrdp/km-00000409.ini to km-${lcid_lower}.ini"
        fi
        log "xrdp: DRY-RUN — would systemctl enable --now xrdp, ufw allow 3389/tcp, chmod 644 /etc/xrdp/key.pem"
        return 0
    fi

    # 1. apt install xrdp + xorgxrdp
    apt_install xrdp xorgxrdp

    # 2. Patch /etc/xrdp/sesman.ini's Policy line to our chosen value (idempotent)
    if [ -f /etc/xrdp/sesman.ini ]; then
        local current
        current=$(grep -E '^Policy=' /etc/xrdp/sesman.ini | head -1 || true)
        local desired="Policy=${SESMAN_POLICY}"
        if [ "$current" != "$desired" ]; then
            run_sudo sed -i "s/^Policy=.*/${desired}/" /etc/xrdp/sesman.ini
            log "xrdp: sesman.ini Policy set to ${SESMAN_POLICY} (was: ${current:-absent})"
        else
            log "xrdp: sesman.ini Policy already ${SESMAN_POLICY}"
        fi
    else
        warn "xrdp: /etc/xrdp/sesman.ini not found even after apt install — skipping Policy patch"
    fi

    # 3. Install reconnectwm.sh (stuck-modifier release after RDP reconnect)
    if [ "$INSTALL_RECONNECTWM" = "true" ] && [ -f "$render/reconnectwm.sh" ]; then
        run_sudo install -m 755 -o root -g root "$render/reconnectwm.sh" /etc/xrdp/reconnectwm.sh
        log "xrdp: installed /etc/xrdp/reconnectwm.sh"
    fi

    # 4. If RDP client locale is non-US-English and matching keymap is missing, mirror the US keymap.
    if [ -n "$RDP_LCID" ] && [ "$RDP_LCID" != "0x00000409" ]; then
        local lcid_short="${RDP_LCID#0x}"
        local lcid_lower="${lcid_short,,}"
        local km_file="/etc/xrdp/km-${lcid_lower}.ini"
        if [ ! -f "$km_file" ] && [ -f /etc/xrdp/km-00000409.ini ]; then
            run_sudo cp /etc/xrdp/km-00000409.ini "$km_file"
            log "xrdp: created $km_file from km-00000409.ini (US fallback)"
        fi
    fi

    # 5. Enable + start xrdp; restart sesman so the new Policy takes effect.
    run_sudo systemctl enable --now xrdp >/dev/null 2>&1 || true
    run_sudo systemctl restart xrdp-sesman >/dev/null 2>&1 || true

    # 6. Open the RDP port through ufw (no-op if ufw is inactive or rule exists).
    if command -v ufw >/dev/null 2>&1; then
        run_sudo ufw allow 3389/tcp >/dev/null 2>&1 || true
    fi

    # 7. Fix /etc/xrdp/key.pem perms so xrdp can use TLS.
    if [ -f /etc/xrdp/key.pem ]; then
        run_sudo chmod 644 /etc/xrdp/key.pem
    fi

    log "xrdp: service enabled, port 3389 opened, key.pem perms set"
}

install_xinitrc() {
    local render="$RENDER_DIR/xinitrc"

    if [ "$DRY_RUN" = 1 ]; then
        log "xinitrc: DRY-RUN — would apt install xorg xinit feh"
        log "xinitrc: DRY-RUN — would install $HOME_DIR/.xinitrc + symlink .xsession"
        return 0
    fi

    apt_install xorg xinit feh
    install -m 755 "$render/xinitrc" "$HOME_DIR/.xinitrc"
    ln -sf "$HOME_DIR/.xinitrc" "$HOME_DIR/.xsession"
    log "xinitrc: installed to $HOME_DIR/.xinitrc (+ .xsession symlink)"
}

install_claude_settings() {
    local render="$RENDER_DIR/claude-settings"

    # Map the role label to its template filename. Three of four match directly;
    # the personal-lab tier carries role: personal in identity.yaml for
    # historical reasons (consumed by other tools too).
    local role="$OPERATOR_ROLE"
    [ "$role" = "personal" ] && role="personal-lab"

    local src="$render/${role}.settings.json"
    [ -f "$src" ] || die "claude-settings: no rendered file at $src (role: $role)"

    local global="$HOME_DIR/.claude/settings.json"
    local hub="$HOME_DIR/$WORKSPACE_HUB_NAME"
    local overlay="$hub/.claude/settings.json"

    if [ "$DRY_RUN" = 1 ]; then
        log "claude-settings: DRY-RUN — would install $src to $global ($role tier)"
        log "claude-settings: DRY-RUN — would install workspace overlay to $overlay"
        return 0
    fi

    # ---- Global file: ~/.claude/settings.json ----
    install -d "$HOME_DIR/.claude"

    if [ -f "$global" ] && [ "$FORCE_CLAUDE_SETTINGS" != 1 ]; then
        install -m 644 "$src" "$global.uap-proposed"
        warn "claude-settings: $global already exists; wrote proposed to $global.uap-proposed — diff and merge manually, or rerun with --force-claude-settings to overwrite."
    else
        install -m 644 "$src" "$global"
        log "claude-settings: installed $global ($role tier)"
    fi

    # ---- Per-workspace overlay: ~/<hub>/.claude/settings.json ----
    install -d "$hub/.claude"

    if [ -f "$overlay" ] && [ "$FORCE_CLAUDE_SETTINGS" != 1 ]; then
        install -m 644 "$render/workspace-overlay.settings.json" "$overlay.uap-proposed"
        warn "claude-settings: $overlay already exists; wrote proposed to $overlay.uap-proposed — diff and merge manually."
    else
        install -m 644 "$render/workspace-overlay.settings.json" "$overlay"
        log "claude-settings: installed workspace overlay at $overlay"
    fi
}

install_gtk_theme() {
    local render="$RENDER_DIR/gtk-theme"

    if [ "$DRY_RUN" = 1 ]; then
        log "gtk-theme: DRY-RUN — would apt install gnome-themes-extra qt5-style-plugins"
        log "gtk-theme: DRY-RUN — would install $HOME_DIR/.config/gtk-{3.0,4.0}/settings.ini and set gsettings color-scheme=prefer-dark + gtk-theme=$GTK_THEME"
        return 0
    fi

    apt_install gnome-themes-extra qt5-style-plugins
    for v in 3.0 4.0; do
        install -d "$HOME_DIR/.config/gtk-$v"
        install -m 644 "$render/gtk-$v/settings.ini" "$HOME_DIR/.config/gtk-$v/settings.ini"
    done
    # Apply via gsettings too (idempotent — gsettings tolerates same value)
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"      2>/dev/null || true
    log "gtk-theme: installed gtk-{3.0,4.0}/settings.ini + gsettings"
}

install_alacritty() {
    local render="$RENDER_DIR/alacritty"
    local target="$HOME_DIR/.config/alacritty"

    if [ "$DRY_RUN" = 1 ]; then
        log "alacritty: DRY-RUN — would apt install alacritty"
        log "alacritty: DRY-RUN — would install $target/alacritty.toml"
        return 0
    fi

    apt_install alacritty
    install -d "$target"
    install -m 644 "$render/alacritty.toml" "$target/alacritty.toml"
    log "alacritty: installed config to $target/alacritty.toml"
}

install_rofi() {
    local render="$RENDER_DIR/rofi"
    local target="$HOME_DIR/.config/rofi"

    if [ "$DRY_RUN" = 1 ]; then
        log "rofi: DRY-RUN — would apt install rofi"
        log "rofi: DRY-RUN — would install $target/tokyo-night.rasi"
        return 0
    fi

    apt_install rofi
    install -d "$target"
    install -m 644 "$render/tokyo-night.rasi" "$target/tokyo-night.rasi"
    log "rofi: installed theme to $target/tokyo-night.rasi"
}

install_plymouth() {
    local theme="$OS_NAME_LOWER"
    local render="$RENDER_DIR/plymouth"
    local target="/usr/share/plymouth/themes/$theme"

    if [ "$DRY_RUN" = 1 ]; then
        log "plymouth: DRY-RUN — would apt install plymouth-themes plymouth-label"
        log "plymouth: DRY-RUN — would install $render/* to $target/"
        diff -q "$render/${theme}.plymouth" "$target/${theme}.plymouth" 2>/dev/null \
            && log "plymouth: .plymouth identical to live" \
            || log "plymouth: .plymouth would change"
        return 0
    fi

    apt_install plymouth-themes plymouth-label
    run_sudo install -d "$target"
    run_sudo install -m 644 "$render/${theme}.plymouth" "$target/${theme}.plymouth"
    run_sudo install -m 644 "$render/${theme}.script"   "$target/${theme}.script"
    run_sudo install -m 644 "$render/logo.png"          "$target/logo.png"

    run_sudo update-alternatives --install \
        /usr/share/plymouth/themes/default.plymouth default.plymouth \
        "$target/${theme}.plymouth" 100 >/dev/null

    run_sudo update-alternatives --set default.plymouth "$target/${theme}.plymouth"

    run_sudo update-initramfs -u >/dev/null
    log "plymouth: installed theme '$theme' and regenerated initramfs"
}

# --- install_apps: operator-facing apps from identity.apps.* --------------
# Browsers, markdown editor, file manager, screenshot tool, terminal tools.
# Each can be apt, snap, or apt-via-third-party-repo — handled in helpers.

install_edge() {
    if dpkg -s microsoft-edge-stable >/dev/null 2>&1; then
        log "apps: microsoft-edge-stable already installed"; return 0
    fi
    log "apps: setting up Microsoft Edge repo + installing edge"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | run_sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
    echo "deb [signed-by=/usr/share/keyrings/microsoft.gpg arch=amd64] https://packages.microsoft.com/repos/edge stable main" \
        | run_sudo tee /etc/apt/sources.list.d/microsoft-edge.list >/dev/null
    APT_UPDATED=0   # force re-update so the new repo is seen
    apt_install microsoft-edge-stable
}

install_chrome() {
    if dpkg -s google-chrome-stable >/dev/null 2>&1; then
        log "apps: google-chrome-stable already installed"; return 0
    fi
    log "apps: setting up Google Chrome repo + installing chrome"
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | run_sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
    echo "deb [signed-by=/usr/share/keyrings/google-chrome.gpg arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main" \
        | run_sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
    APT_UPDATED=0
    apt_install google-chrome-stable
}

install_typora() {
    if dpkg -s typora >/dev/null 2>&1; then
        log "apps: typora already installed"; return 0
    fi
    log "apps: setting up Typora repo + installing typora"
    curl -fsSL https://typora.io/linux/public-key.asc \
        | run_sudo gpg --dearmor -o /usr/share/keyrings/typora.gpg
    echo "deb [signed-by=/usr/share/keyrings/typora.gpg] https://typora.io/linux ./" \
        | run_sudo tee /etc/apt/sources.list.d/typora.list >/dev/null
    APT_UPDATED=0
    apt_install typora
    # Inconsolata for the monospace theme (Typora monospace theme expects it).
    apt_install fonts-inconsolata
}

install_apps() {
    # Pull the apps lists from identity.yaml.
    local -a browsers terminal_tools
    mapfile -t browsers       < <(yq '.apps.browsers[]'        "$IDENTITY" 2>/dev/null)
    mapfile -t terminal_tools < <(yq '.apps.terminal_tools[]'  "$IDENTITY" 2>/dev/null)
    local markdown_editor file_manager screenshot
    markdown_editor=$(yq '.apps.markdown_editor // ""' "$IDENTITY")
    file_manager=$(yq    '.apps.file_manager    // ""' "$IDENTITY")
    screenshot=$(yq      '.apps.screenshot      // ""' "$IDENTITY")

    if [ "$DRY_RUN" = 1 ]; then
        log "apps: DRY-RUN — would install browsers=[${browsers[*]}] editor=$markdown_editor tools=[${terminal_tools[*]}] file-mgr=$file_manager screenshot=$screenshot"
        return 0
    fi

    # Browsers
    local b
    for b in "${browsers[@]}"; do
        case "$b" in
            edge)     install_edge ;;
            chrome)   install_chrome ;;
            chromium) run_sudo snap install chromium ;;
            firefox)  run_sudo snap install firefox ;;
            brave|"") : ;;
            *)        warn "apps: unknown browser '$b' — skipping" ;;
        esac
    done

    # Markdown editor
    case "$markdown_editor" in
        typora) install_typora ;;
        none|"") : ;;
        *)      warn "apps: unknown markdown_editor '$markdown_editor' — skipping" ;;
    esac

    # Terminal tools
    local t
    for t in "${terminal_tools[@]}"; do
        case "$t" in
            btop|bat|vim|tmux|jq|fd-find|ripgrep|neovim|htop) apt_install "$t" ;;
            glow)    run_sudo snap install glow ;;
            "")      : ;;
            *)       apt_install "$t" ;;
        esac
    done

    # File manager
    case "$file_manager" in
        thunar|nautilus|dolphin|pcmanfm) apt_install "$file_manager" ;;
        none|"") : ;;
        *)       warn "apps: unknown file_manager '$file_manager' — skipping" ;;
    esac

    # Screenshot tool
    case "$screenshot" in
        flameshot) apt_install flameshot ;;
        scrot)     apt_install scrot ;;
        gnome-screenshot) apt_install gnome-screenshot ;;
        none|"")   : ;;
        *)         warn "apps: unknown screenshot tool '$screenshot' — skipping" ;;
    esac

    log "apps: installed selected operator apps from identity.apps.*"
}

# --- Drive components -----------------------------------------------------

# Pick the list of components to run
if [ "${#COMPONENTS_REQUESTED[@]}" -gt 0 ]; then
    COMPONENTS=("${COMPONENTS_REQUESTED[@]}")
else
    mapfile -t COMPONENTS < <(yq '.components_enabled[]' "$IDENTITY")
fi

[ "${#COMPONENTS[@]}" -eq 0 ] && die "no components selected (identity.components_enabled is empty?)."

log "identity: ${OS_NAME} (${OS_NAME_LOWER}) — '${TAGLINE}' — operator ${USERNAME}"
log "components: ${COMPONENTS[*]}"

for component in "${COMPONENTS[@]}"; do
    render_component "$component"
    install_hook="install_${component//-/_}"
    if declare -F "$install_hook" >/dev/null; then
        "$install_hook"
    else
        warn "$component: no install_$component() hook defined yet — rendered only, not installed."
    fi
done

log "done."
