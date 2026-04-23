---
description: Swap this tmux pane to the child of the current /branch session (or list if multiple)
allowed-tools: Bash(cctree:*)
---

!`cctree --down --jump-inplace`

Display the output above verbatim to the user. Do not summarize, comment, or add analysis. The `[HH:MM:SS]` timestamp in the "pane swap queued" line marks the moment the swap was requested — on a replayed session (resumed from history), the timestamp will be old and no new swap fires. With multiple children the swap is skipped and the listing is shown — rerun `cctree --down --sid <prefix> --jump-inplace` (or `/exit` and `claude --resume <sid>` manually) to pick one.
