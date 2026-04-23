---
description: Open the parent of the current /branch session in a new tmux pane
allowed-tools: Bash(cctree:*)
---

!`cctree --up --jump`

Display the output above verbatim to the user. Do not summarize, comment, or add analysis. If the spawn failed (no tmux, etc.), the output already includes a `claude --resume …` line the user can run manually after `/exit`.
