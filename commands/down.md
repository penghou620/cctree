---
description: Show the /branch children of the current session (sessions forked from here)
allowed-tools: Bash(cctree:*)
---

!`cctree --down`

Display the output above verbatim to the user. Do not summarize, comment, or add analysis. If the user asks to actually switch to one of those sessions, instruct them to run `/exit` and then the `claude --resume <sid>` line using the sid they want.
