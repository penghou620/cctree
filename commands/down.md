---
description: Open the /branch child of the current session in a new tmux pane (or list if multiple)
allowed-tools: Bash(cctree:*)
---

!`cctree --down --jump`

Display the output above verbatim to the user. Do not summarize, comment, or add analysis. If there are multiple children, the output lists them and the user must rerun with the specific sid (or `/exit` and `claude --resume <sid>` manually).
