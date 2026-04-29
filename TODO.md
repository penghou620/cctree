# cctree TODO

## Robustness / scope
- Cross-window detection — `find_active_claude_session` only looks in the current tmux session's panes (`list-panes -s`). If you have multiple windows, the sidebar goes blank when you switch windows. Showing live `●` markers for all live claudes regardless of pane (we already track `live_sids`) plus following the focused window would fix this.
- fsevents/inotify instead of full re-glob — `load_sessions()` re-globs `~/.claude/projects/*/*.jsonl` every tick. The mtime cache helps, but the directory scan itself is O(N). At ~1s intervals × thousands of files this adds up. Watching the projects dir would let us drop the interval and react instantly.
- Configurable auto-collapse threshold — `AUTO_COLLAPSE_OLDER_THAN_SECONDS = 24*3600` is hardcoded. One env var (`CCTREE_AUTO_COLLAPSE_HOURS`) is cheap.

## Code health
- Tests — there are none. The parser (`scan_session`, preamble detection, title inheritance) and the tree builder (root detection, collapse logic) are pure functions and trivial to cover.
- Split the 1175-line script — it works fine as a single file, but `parser.py` / `tmux.py` / `render.py` / `watch.py` would make the watch loop's state machine easier to reason about. Low priority; only worth doing if we start adding the features above.
