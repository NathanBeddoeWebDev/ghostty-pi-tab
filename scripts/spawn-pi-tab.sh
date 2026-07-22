#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <working-directory> <prompt>\n' "$0" >&2
  exit 2
fi

working_directory=$1
prompt=$2

if [[ $(uname -s) != Darwin ]]; then
  printf 'ghostty-pi-tab requires macOS.\n' >&2
  exit 1
fi

if [[ ${TERM_PROGRAM:-} != ghostty ]]; then
  printf 'ghostty-pi-tab must run inside Ghostty.\n' >&2
  exit 1
fi

if [[ ! -d $working_directory ]]; then
  printf 'Working directory does not exist: %s\n' "$working_directory" >&2
  exit 1
fi

if [[ -z $prompt ]]; then
  printf 'Prompt must be non-empty.\n' >&2
  exit 1
fi

if ! command -v osascript >/dev/null 2>&1; then
  printf 'osascript is unavailable.\n' >&2
  exit 1
fi

if ! command -v pi >/dev/null 2>&1; then
  printf 'pi is unavailable on PATH.\n' >&2
  exit 1
fi

working_directory=$(cd "$working_directory" && pwd -P)
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
rename_helper=$script_directory/rename-current-tab.sh
pi_prompt_runner=$script_directory/run-pi-prompt.sh

if [[ ! -x $rename_helper ]]; then
  printf 'Tab rename helper is unavailable: %s\n' "$rename_helper" >&2
  exit 1
fi

if [[ ! -x $pi_prompt_runner ]]; then
  printf 'Pi prompt runner is unavailable: %s\n' "$pi_prompt_runner" >&2
  exit 1
fi

printf -v rename_command 'bash %q "<concise task title>"' "$rename_helper"
dispatch_prompt=$(printf '%s\n\n%s\n%s' \
  'Once you understand the task well enough to name it, rename this Ghostty tab to a concise, task-specific title (ideally 2-5 words) before doing substantive work.' \
  "Run: $rename_command" \
  "Task: $prompt")

prompt_file=
cleanup_prompt_file() {
  if [[ -n ${prompt_file:-} ]]; then
    rm -f -- "$prompt_file"
  fi
}
trap cleanup_prompt_file EXIT HUP INT TERM

prompt_directory=${TMPDIR:-/tmp}
if [[ ! -d $prompt_directory || ! -w $prompt_directory ]]; then
  printf 'Temporary directory is unavailable: %s\n' "$prompt_directory" >&2
  exit 1
fi

umask 077
prompt_file=$(mktemp "$prompt_directory/ghostty-pi-tab.prompt.XXXXXX")
printf '%s\n' "$dispatch_prompt" >"$prompt_file"
chmod 600 "$prompt_file"
prompt=
dispatch_prompt=

# Tool subprocesses do not necessarily inherit stdin from the terminal. Walk
# upward until we find the controlling TTY owned by the Pi session.
caller_tty=
pid=$$
while [[ $pid =~ ^[0-9]+$ && $pid -gt 1 ]]; do
  tty_name=$(ps -p "$pid" -o tty= 2>/dev/null | tr -d '[:space:]')
  if [[ -n $tty_name && $tty_name != '??' ]]; then
    if [[ $tty_name == /* ]]; then
      caller_tty=$tty_name
    else
      caller_tty=/dev/$tty_name
    fi
    break
  fi
  pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]')
done

if [[ -z $caller_tty || ! -c $caller_tty || ! -w $caller_tty ]]; then
  printf 'Could not determine the invoking Ghostty terminal.\n' >&2
  exit 1
fi

marker_title="__ghostty_pi_tab_${$}_${RANDOM}__"

osascript - "$working_directory" "$prompt_file" "$pi_prompt_runner" "$caller_tty" "$marker_title" <<'APPLESCRIPT'
on writeTerminalTitle(ttyPath, titleText)
    do shell script "/usr/bin/printf '\\033]2;%s\\007' " & ¬
        quoted form of titleText & " > " & quoted form of ttyPath
end writeTerminalTitle

on run argv
    set projectDir to item 1 of argv
    set promptFile to item 2 of argv
    set piPromptRunner to item 3 of argv
    set sourceTTY to item 4 of argv
    set markerTitle to item 5 of argv
    set commandText to "cd -- " & quoted form of projectDir & ¬
        " && bash " & quoted form of piPromptRunner & ¬
        " " & quoted form of promptFile
    set markerWritten to false
    set originalTitle to ""

    try
        -- Ghostty 1.3 does not expose each terminal's TTY to AppleScript.
        -- Mark the caller's TTY with a unique title so its terminal and
        -- containing window can be identified independently of GUI focus.
        set terminalSnapshots to {}
        tell application "Ghostty"
            if (count of windows) is 0 then
                error "Ghostty has no open window."
            end if

            repeat with candidateWindow in (get windows)
                repeat with candidateTerm in (get terminals of candidateWindow)
                    set end of terminalSnapshots to ¬
                        {(get id of candidateTerm), (get name of candidateTerm)}
                end repeat
            end repeat
        end tell

        my writeTerminalTitle(sourceTTY, markerTitle)
        set markerWritten to true
        delay 0.1

        tell application "Ghostty"
            set targetWindow to missing value
            set sourceTerm to missing value

            repeat with candidateWindow in (get windows)
                repeat with candidateTerm in (get terminals of candidateWindow)
                    if (get name of candidateTerm) is markerTitle then
                        set targetWindow to candidateWindow
                        set sourceTerm to candidateTerm
                        exit repeat
                    end if
                end repeat
                if targetWindow is not missing value then exit repeat
            end repeat

            if targetWindow is missing value then
                error "Could not identify the invoking Ghostty window."
            end if
            set sourceID to get id of sourceTerm
        end tell

        repeat with terminalSnapshot in terminalSnapshots
            if item 1 of terminalSnapshot is sourceID then
                set originalTitle to item 2 of terminalSnapshot
                exit repeat
            end if
        end repeat
        my writeTerminalTitle(sourceTTY, originalTitle)
        set markerWritten to false

        tell application "Ghostty"
            set existingTabIDs to id of every tab of targetWindow
            activate window targetWindow
            perform action "new_tab" on sourceTerm

            delay 1

            set targetTab to missing value
            repeat with candidateTab in (get tabs of targetWindow)
                if existingTabIDs does not contain (get id of candidateTab) then
                    set targetTab to candidateTab
                    exit repeat
                end if
            end repeat
            if targetTab is missing value then
                error "Ghostty did not create a tab in the invoking window."
            end if

            set targetTerm to focused terminal of targetTab

            -- The new tab can receive a user keystroke while it is being
            -- created and focused. Clear any partial shell input, paste the
            -- command, then submit it with an explicit Return keystroke.
            send key "u" modifiers "control" to targetTerm
            input text commandText to targetTerm
            send key "enter" to targetTerm
        end tell
    on error errorMessage number errorNumber
        if markerWritten then
            try
                my writeTerminalTitle(sourceTTY, originalTitle)
            end try
        end if
        error errorMessage number errorNumber
    end try
end run
APPLESCRIPT

# The runner in the new tab now owns deletion of the private prompt file.
prompt_file=
printf 'Launched Pi in a new Ghostty tab.\n'
