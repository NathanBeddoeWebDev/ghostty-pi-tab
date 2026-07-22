---
name: ghostty-pi-tab
description: Launch a Pi session in a new Ghostty tab on macOS. Use when the user asks to open another Ghostty tab and run a Pi prompt there.
license: MIT
compatibility: macOS; Ghostty 1.3+ with AppleScript enabled; pi available on the shell PATH; must be invoked from Pi running inside Ghostty.
---

# Ghostty Pi Tab

Treat each launch as a **dispatch**: an independent Pi session receives one bounded prompt and the current user's permissions.

## Steps

1. Establish the dispatch contract.
   - Require explicit intent to launch another Pi session.
   - Use the user's requested working directory, or the current working directory when none is specified.
   - Pass the requested task as the prompt. When the task is missing or ambiguous, ask for it.
   - The helper adds a dispatch instruction requiring the new Pi to choose a concise, task-specific Ghostty tab title once it understands the task.

   Complete when the working directory exists and the launch prompt is non-empty.

2. Run [`scripts/spawn-pi-tab.sh`](scripts/spawn-pi-tab.sh) with the working directory and prompt as separate quoted arguments:

   ```bash
   bash <skill-directory>/scripts/spawn-pi-tab.sh "$PWD" "<prompt>"
   ```

   The helper identifies the invoking Pi terminal from its controlling TTY, saves that terminal's Ghostty window independently of GUI focus, and uses the tested `perform action "new_tab"` path in that window only. It writes the dispatch prompt to a mode-`600` temporary file so prompt text is not exposed in shell history or process arguments, then [`scripts/run-pi-prompt.sh`](scripts/run-pi-prompt.sh) starts interactive Pi from that file and deletes it when Pi exits. The dispatched Pi is instructed to call [`scripts/rename-current-tab.sh`](scripts/rename-current-tab.sh) with a concise title before substantive work. Its shell remains available when Pi exits.

   Complete when the helper exits successfully and prints `Launched Pi in a new Ghostty tab.`

3. Report the dispatch.
   - State the working directory and summarize the prompt sent.
   - State that the new Pi is an independent session; coordination and results do not return automatically.

   Complete when the user can identify what was launched and where.

## Failure reference

- An Automation permission failure requires allowing the caller to control Ghostty in **System Settings → Privacy & Security → Automation**, then retrying once.
- A missing Ghostty window requires opening one before retrying.
- A `must run inside Ghostty` failure means `TERM_PROGRAM` does not identify the invoking terminal as Ghostty.
- A `Could not determine the invoking Ghostty terminal.` failure means the helper was not launched as a descendant of the Pi process running in Ghostty.
- Prompt text still becomes part of Pi's saved session and is sent to the configured model provider; the temporary file only prevents additional exposure through shell history and process arguments.
- Report any other `osascript` error verbatim; the launch state is uncertain after an AppleScript error.
