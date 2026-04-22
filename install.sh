#!/usr/bin/env bash
#
# cctree installer
#
#   curl -fsSL https://raw.githubusercontent.com/penghou620/cctree/main/install.sh | bash
#
# Env overrides:
#   CCTREE_REPO_URL                default: https://github.com/penghou620/cctree.git
#   CCTREE_INSTALL_DIR             default: ~/.local/share/cctree
#   CCTREE_BIN_DIR                 default: ~/.local/bin
#   CCTREE_INSTALL_TMUX_BINDING    yes | no | ask  (default: ask when stdin is a tty, else no)

set -euo pipefail

REPO_URL="${CCTREE_REPO_URL:-https://github.com/penghou620/cctree.git}"
INSTALL_DIR="${CCTREE_INSTALL_DIR:-$HOME/.local/share/cctree}"
BIN_DIR="${CCTREE_BIN_DIR:-$HOME/.local/bin}"
TMUX_CONF="$HOME/.tmux.conf"

_color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info() { printf '%s %s\n' "$(_color 36 '::')" "$*"; }
warn() { printf '%s %s\n' "$(_color 33 '!!')" "$*"; }
die()  { printf '%s %s\n' "$(_color 31 'xx')" "$*" >&2; exit 1; }

command -v git     >/dev/null 2>&1 || die "git not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
  info "updating existing checkout at $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only --quiet
else
  info "cloning $REPO_URL -> $INSTALL_DIR"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --depth 1 --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# Symlink binaries
mkdir -p "$BIN_DIR"
for name in cctree cctree-sidebar; do
  src="$INSTALL_DIR/$name"
  dst="$BIN_DIR/$name"
  [ -f "$src" ] || die "missing $src in repo — checkout looks incomplete"
  chmod +x "$src"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    :
  else
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      warn "$dst exists and is not a symlink — backing up to $dst.bak"
      mv "$dst" "$dst.bak"
    fi
    ln -sfn "$src" "$dst"
  fi
  info "linked $dst"
done

# PATH check
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH — add this to your shell rc:"
     printf '       %s\n' "export PATH=\"$BIN_DIR:\$PATH\""
     ;;
esac

# Slash commands (~/.claude/commands/{up,down}.md)
CMD_DIR="$HOME/.claude/commands"
mkdir -p "$CMD_DIR"
for name in up down; do
  src="$INSTALL_DIR/commands/$name.md"
  dst="$CMD_DIR/$name.md"
  if [ ! -f "$src" ]; then continue; fi
  if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
    warn "$dst exists and differs — leaving yours in place (remove it to take the new version)"
    continue
  fi
  cp "$src" "$dst"
  info "installed slash command /$name"
done

# Tmux binding
mode="${CCTREE_INSTALL_TMUX_BINDING:-ask}"
if [ "$mode" = "ask" ]; then
  if [ -t 0 ] && command -v tmux >/dev/null 2>&1; then
    printf '%s Add tmux binding (prefix + C-c toggles sidebar)? [y/N] ' "$(_color 36 '::')"
    read -r reply
    case "$reply" in y|Y|yes|YES) mode="yes" ;; *) mode="no" ;; esac
  else
    mode="no"
  fi
fi

if [ "$mode" = "yes" ]; then
  if [ -f "$TMUX_CONF" ] && grep -Fq 'cctree-sidebar' "$TMUX_CONF"; then
    info "tmux binding already present in $TMUX_CONF"
  else
    {
      printf '\n##### cctree\n'
      printf '# toggle a cctree --watch sidebar in the current window\n'
      printf 'bind C-c run-shell "cctree-sidebar"\n'
    } >> "$TMUX_CONF"
    info "appended tmux binding to $TMUX_CONF"
    info "reload now: tmux source-file ~/.tmux.conf"
  fi
else
  info "skipped tmux binding (set CCTREE_INSTALL_TMUX_BINDING=yes to add automatically)"
fi

echo
info "$(_color 32 'cctree installed')  try:  cctree --help"
