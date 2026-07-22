#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <tab-title>\n' "$0" >&2
  exit 2
fi

tab_title=$1

if [[ $(uname -s) != Darwin ]]; then
  printf 'rename-current-tab requires macOS.\n' >&2
  exit 1
fi

if [[ ${TERM_PROGRAM:-} != ghostty ]]; then
  printf 'rename-current-tab must run inside Ghostty.\n' >&2
  exit 1
fi

if [[ -z $tab_title ]]; then
  printf 'Tab title must be non-empty.\n' >&2
  exit 1
fi

if [[ $tab_title =~ [[:cntrl:]] ]]; then
  printf 'Tab title must not contain control characters.\n' >&2
  exit 1
fi

if ((${#tab_title} > 80)); then
  printf 'Tab title must be 80 characters or fewer.\n' >&2
  exit 1
fi

if ! command -v osascript >/dev/null 2>&1; then
  printf 'osascript is unavailable.\n' >&2
  exit 1
fi

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

marker_title="__ghostty_pi_tab_title_${$}_${RANDOM}__"

osascript - "$caller_tty" "$marker_title" "$tab_title" <<'APPLESCRIPT'
on writeTerminalTitle(ttyPath, titleText)
    do shell script "/usr/bin/printf '\\033]2;%s\\007' " & ¬
        quoted form of titleText & " > " & quoted form of ttyPath
end writeTerminalTitle

on run argv
    set sourceTTY to item 1 of argv
    set markerTitle to item 2 of argv
    set tabTitle to item 3 of argv
    set markerWritten to false
    set originalTitle to ""

    try
        set terminalSnapshots to {}
        tell application "Ghostty"
            if (count of windows) is 0 then
                error "Ghostty has no open window."
            end if

            repeat with candidateTerm in (get terminals)
                set end of terminalSnapshots to ¬
                    {(get id of candidateTerm), (get name of candidateTerm)}
            end repeat
        end tell

        -- Ghostty 1.3 does not expose each terminal's TTY to AppleScript.
        -- Give the caller's TTY a unique title so we can target its terminal
        -- regardless of which Ghostty window or tab currently has GUI focus.
        my writeTerminalTitle(sourceTTY, markerTitle)
        set markerWritten to true
        delay 0.1

        tell application "Ghostty"
            set sourceTerm to missing value
            repeat with candidateTerm in (get terminals)
                if (get name of candidateTerm) is markerTitle then
                    set sourceTerm to candidateTerm
                    exit repeat
                end if
            end repeat

            if sourceTerm is missing value then
                error "Could not identify the invoking Ghostty tab."
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
            perform action ("set_tab_title:" & tabTitle) on sourceTerm
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

printf 'Renamed current Ghostty tab to: %s\n' "$tab_title"
