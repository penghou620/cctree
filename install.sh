#!/usr/bin/env bash
#
# cctree installer
#
#   curl -fsSL https://raw.githubusercontent.com/penghou620/cctree/main/install.sh | bash
#
# Prompts interactively when stdin or /dev/tty is available. Set any of these
# env vars to skip the matching prompt:
#
#   CCTREE_REPO_URL                default: https://github.com/penghou620/cctree.git
#   CCTREE_INSTALL_DIR             default: ~/.local/share/cctree
#   CCTREE_BIN_DIR                 default: ~/.local/bin
#   CCTREE_INSTALL_TMUX_BINDING    yes | no | ask  (default: ask when a tty is available, else no)

set -euo pipefail

TMUX_CONF="$HOME/.tmux.conf"

_color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info() { printf '%s %s\n' "$(_color 36 '::')" "$*"; }
warn() { printf '%s %s\n' "$(_color 33 '!!')" "$*"; }
die()  { printf '%s %s\n' "$(_color 31 'xx')" "$*" >&2; exit 1; }

command -v git     >/dev/null 2>&1 || die "git not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"

# Find a tty for prompts. /dev/tty works even under `curl | bash` where stdin
# is the pipe; fall back to stdin if it's a tty; otherwise no prompts.
# (On macOS `[ -r /dev/tty ]` can return true with no controlling terminal, so
# probe by actually opening it.)
TTY_IN=""
if (: < /dev/tty) >/dev/null 2>&1; then
  TTY_IN="/dev/tty"
elif [ -t 0 ]; then
  TTY_IN="/dev/stdin"
fi

expand_home() {
  case "$1" in
    "~")    printf '%s' "$HOME" ;;
    "~/"*)  printf '%s' "$HOME/${1#~/}" ;;
    *)      printf '%s' "$1" ;;
  esac
}

prompt_path() {
  # prompt_path <label> <default>  ->  prints chosen path
  local label="$1" default="$2" reply
  if [ -z "$TTY_IN" ]; then
    printf '%s' "$default"
    return
  fi
  printf '%s %s [%s]: ' "$(_color 36 '::')" "$label" "$default" >/dev/tty
  IFS= read -r reply <"$TTY_IN" || reply=""
  [ -n "$reply" ] || reply="$default"
  expand_home "$reply"
}

prompt_yn() {
  # prompt_yn <label> <default yes|no>  ->  prints yes or no
  local label="$1" default="$2" reply hint
  case "$default" in
    yes) hint="[Y/n]" ;;
    *)   hint="[y/N]" ;;
  esac
  if [ -z "$TTY_IN" ]; then
    printf '%s' "$default"
    return
  fi
  printf '%s %s %s ' "$(_color 36 '::')" "$label" "$hint" >/dev/tty
  IFS= read -r reply <"$TTY_IN" || reply=""
  case "$reply" in
    y|Y|yes|YES) printf 'yes' ;;
    n|N|no|NO)   printf 'no' ;;
    "")          printf '%s' "$default" ;;
    *)           printf 'no' ;;
  esac
}

# Resolve config: env var wins, otherwise prompt (or default if no tty).
REPO_URL="${CCTREE_REPO_URL:-https://github.com/penghou620/cctree.git}"

if [ -n "${CCTREE_INSTALL_DIR:-}" ]; then
  INSTALL_DIR="$CCTREE_INSTALL_DIR"
else
  INSTALL_DIR="$(prompt_path 'Clone cctree to' "$HOME/.local/share/cctree")"
fi

if [ -n "${CCTREE_BIN_DIR:-}" ]; then
  BIN_DIR="$CCTREE_BIN_DIR"
else
  BIN_DIR="$(prompt_path 'Symlink binaries into' "$HOME/.local/bin")"
fi

tmux_mode="${CCTREE_INSTALL_TMUX_BINDING:-ask}"
if [ "$tmux_mode" = "ask" ]; then
  if command -v tmux >/dev/null 2>&1; then
    tmux_mode="$(prompt_yn 'Add tmux binding (prefix + C-c toggles sidebar)?' 'no')"
  else
    tmux_mode="no"
  fi
fi

# Clone or update. Re-runs reuse an existing checkout; if the directory exists
# but isn't a git repo we bail rather than clobber it.
if [ -d "$INSTALL_DIR/.git" ]; then
  info "updating existing checkout at $INSTALL_DIR"
  if ! git -C "$INSTALL_DIR" pull --ff-only --quiet 2>/dev/null; then
    warn "git pull failed (local changes or non-fast-forward?) — keeping checkout as-is"
  fi
elif [ -e "$INSTALL_DIR" ]; then
  die "$INSTALL_DIR exists but is not a git checkout — remove it or pick a different CCTREE_INSTALL_DIR"
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
    info "$dst already linked"
    continue
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    bak="$dst.bak"
    [ -e "$bak" ] && bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    warn "$dst exists and is not a symlink — backing up to $bak"
    mv "$dst" "$bak"
  fi
  ln -sfn "$src" "$dst"
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
  if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      info "slash command /$name already up to date"
      continue
    fi
    warn "$dst exists and differs — leaving yours in place (remove it to take the new version)"
    continue
  fi
  cp "$src" "$dst"
  info "installed slash command /$name"
done

# Tmux binding
if [ "$tmux_mode" = "yes" ]; then
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
