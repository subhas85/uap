#!/usr/bin/env bash
#
# bootstrap.sh — kickstart a UAP deployment from a fresh Ubuntu Server 24.04.
#
# What this does:
#   1. Sanity-checks the OS, refuses to run as root.
#   2. Installs minimal apt prereqs (git, curl, ca-certificates, build deps).
#   3. Installs Claude Code CLI if missing.
#   4. Ensures the UAP repo is at ~/uap (clones from REPO_URL if not yet there).
#   5. Launches `claude` in ~/uap/setup/ so the deployment wizard starts.
#
# Idempotent — re-running is safe.
#
# Usage:
#   # If you already have the repo cloned to ~/uap:
#   bash ~/uap/bootstrap.sh
#
#   # One-liner from the public repo:
#   bash <(curl -fsSL https://raw.githubusercontent.com/subhas85/uap/main/bootstrap.sh)
#
# Env vars:
#   REPO_URL — git URL to clone if ~/uap isn't already present.
#              Defaults to https://github.com/subhas85/uap.git (the public repo).
#              Forks should override to their own URL.
#   SKIP_WIZARD=1 — set up everything but don't auto-launch the wizard.
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/subhas85/uap.git}"
UAP_DIR="$HOME/uap"
LOG_PREFIX="\033[1;36m[uap-bootstrap]\033[0m"

log() { printf "${LOG_PREFIX} %s\n" "$*"; }
err() { printf "\033[1;31m[uap-bootstrap]\033[0m %s\n" "$*" >&2; }

# --- Refuse root ----------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
  err "Run as your normal user (not root). The script will sudo when needed."
  exit 1
fi

# --- OS check -------------------------------------------------------------

if [ ! -r /etc/os-release ]; then
  err "Cannot read /etc/os-release — is this Ubuntu?"
  exit 1
fi
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  err "This script targets Ubuntu. Detected: ${ID:-unknown}. Aborting."
  exit 1
fi
if [ "${VERSION_ID:-}" != "24.04" ]; then
  log "WARNING: tested on Ubuntu 24.04 LTS; detected ${VERSION_ID:-?}. Continuing — your mileage may vary."
fi

# --- Minimal apt prereqs --------------------------------------------------

NEED_APT=()
for pkg in git curl ca-certificates; do
  dpkg -s "$pkg" >/dev/null 2>&1 || NEED_APT+=("$pkg")
done
if [ "${#NEED_APT[@]}" -gt 0 ]; then
  log "Installing apt prereqs: ${NEED_APT[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${NEED_APT[@]}"
else
  log "apt prereqs already present."
fi

# --- yq (Mike Farah's Go yq, required by apply.sh) ------------------------
# apt's "yq" is the Python version with different syntax. apply.sh needs Go yq.
# Install via direct download to ~/.local/bin/ to avoid the apt confusion.

YQ_VERSION="v4.45.4"
if ! command -v yq >/dev/null 2>&1 || ! yq --version 2>&1 | grep -q "mikefarah"; then
  log "Installing yq (Mike Farah's Go yq, ${YQ_VERSION}) to ~/.local/bin/"
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    -o "$HOME/.local/bin/yq"
  chmod +x "$HOME/.local/bin/yq"
  export PATH="$HOME/.local/bin:$PATH"
  yq --version
else
  log "yq already installed: $(yq --version)"
fi

# --- Claude Code CLI ------------------------------------------------------

if command -v claude >/dev/null 2>&1; then
  log "Claude Code already installed: $(claude --version 2>&1 | head -1)"
else
  log "Installing Claude Code CLI..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v claude >/dev/null 2>&1; then
    err "Claude Code install completed but 'claude' is not on PATH."
    err "Check ~/.local/bin/claude; ensure ~/.local/bin is on PATH and re-run."
    exit 1
  fi
fi

# --- Persist ~/.local/bin on PATH for future shells (idempotent) ----------
# Claude Code installs to ~/.local/bin/claude. The export above covers this
# script's process; this block makes the path stick for fresh SSH/tty shells.
# Marker-based idempotence — re-running bootstrap.sh won't duplicate the block.

BASHRC="$HOME/.bashrc"
UAP_MARKER='# UAP bootstrap: ensure ~/.local/bin is on PATH (for claude, etc.)'
if [ -d "$HOME/.local/bin" ] && [ -f "$BASHRC" ] && ! grep -qsF "$UAP_MARKER" "$BASHRC"; then
  {
    printf '\n%s\n' "$UAP_MARKER"
    printf 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac\n'
  } >> "$BASHRC"
  log "appended ~/.local/bin PATH guard to $BASHRC"
elif [ -f "$BASHRC" ] && grep -qsF "$UAP_MARKER" "$BASHRC"; then
  log "~/.bashrc already has the UAP PATH guard — leaving alone."
fi

# --- Get the UAP repo ----------------------------------------------------

if [ -d "$UAP_DIR/.git" ]; then
  log "UAP repo already at $UAP_DIR — pulling latest."
  git -C "$UAP_DIR" pull --ff-only || log "(pull skipped; not on a branch or no remote)"
elif [ -d "$UAP_DIR" ] && [ -f "$UAP_DIR/README.md" ]; then
  log "UAP folder at $UAP_DIR exists but isn't a git checkout — leaving it alone."
else
  log "Cloning UAP repo from $REPO_URL → $UAP_DIR"
  git clone "$REPO_URL" "$UAP_DIR"
fi

# --- Launch the wizard ---------------------------------------------------

if [ "${SKIP_WIZARD:-}" = "1" ]; then
  log "SKIP_WIZARD=1 set — not launching the setup wizard."
  log "Run it manually with:  cd ~/uap/setup && claude"
  exit 0
fi

log "Launching the UAP setup wizard."
log "Claude will read setup/CLAUDE.md and walk you through the questionnaire."
log ""
cd "$UAP_DIR/setup"
exec claude --permission-mode=bypassPermissions
