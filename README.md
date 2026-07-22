# Ghostty Pi Tab

An Agent Skill that dispatches an independent Pi coding-agent session into a new tab in the **same Ghostty window as the invoking Pi session**.

The dispatched Pi receives the requested working directory and task, chooses a concise task-specific tab title, and leaves its shell open when Pi exits.

## Requirements

- macOS
- Ghostty 1.3 or newer with AppleScript enabled (`macos-applescript = true`, the default)
- Pi available as `pi` on `PATH`
- Bash
- Invocation from a Pi session running inside Ghostty

The first launch may trigger a macOS Automation permission prompt. The calling application must be allowed to control Ghostty under **System Settings → Privacy & Security → Automation**.

## Installation

Clone the repository into a directory Pi scans for skills:

```bash
git clone <repository-url> ~/.agents/skills/ghostty-pi-tab
```

Alternatively, place this directory under another supported skill location and ensure `SKILL.md` remains at its root.

## Usage

Ask Pi to open a new Ghostty tab and give the new Pi a task, for example:

> Open a new Pi tab and have it investigate issue #42 in this repository.

The skill requires explicit launch intent and will use the current working directory unless another directory is requested.

## Security and privacy

Review this repository before installing it. Agent skills can instruct Pi to execute scripts, and the dispatched Pi has the same operating-system permissions as the current user.

This skill:

- Controls Ghostty through macOS AppleScript automation.
- Starts an independent Pi session with the current user's permissions and configured tools.
- Does not perform network requests itself. Pi and the selected model provider may perform their normal network operations.
- Stores the dispatch prompt in a mode-`600` temporary file rather than putting prompt text in shell history or process arguments.
- Deletes that temporary prompt file when the dispatched Pi exits. An abrupt machine or process termination can leave the private file in the system temporary directory.
- Does not hide the prompt from Pi: it remains in Pi's session storage and is sent to the configured model provider.
- Briefly changes and restores the invoking terminal title to identify its exact Ghostty window. This is a compatibility workaround because Ghostty 1.3 does not expose terminal TTYs through AppleScript.

Do not include secrets in dispatched prompts unless they are appropriate for Pi's session storage and model provider.

## Implementation notes

- `scripts/spawn-pi-tab.sh` finds the invoking Pi process's controlling TTY, identifies its Ghostty window, and creates the tab in that window only.
- `scripts/run-pi-prompt.sh` validates the private prompt file, starts Pi using an `@file` argument, and removes the file on exit.
- `scripts/rename-current-tab.sh` identifies the calling tab independently of GUI focus and applies a persistent Ghostty tab-title override.

Tab titles must be non-empty, at most 80 characters, and contain no control characters.

## License

MIT. See [LICENSE](LICENSE).
