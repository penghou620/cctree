---
description: Swap this tmux pane to the parent of the current /branch session
allowed-tools: Bash(cctree:*)
---

!`cctree --up --jump-inplace`

Display the output above verbatim to the user. Do not summarize, comment, or add analysis. The swap fires after the current response finishes streaming; if --jump-inplace can't run (e.g. not in tmux), the printed `claude --resume …` line is the manual fallback.
