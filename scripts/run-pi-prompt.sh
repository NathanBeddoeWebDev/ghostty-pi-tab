#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <prompt-file>\n' "$0" >&2
  exit 2
fi

prompt_file=$1

if [[ $(uname -s) != Darwin ]]; then
  printf 'run-pi-prompt requires macOS.\n' >&2
  exit 1
fi

if [[ ${TERM_PROGRAM:-} != ghostty ]]; then
  printf 'run-pi-prompt must run inside Ghostty.\n' >&2
  exit 1
fi

if [[ ! -f $prompt_file || -L $prompt_file || ! -O $prompt_file ]]; then
  printf 'Prompt file must be a regular file owned by the current user: %s\n' "$prompt_file" >&2
  exit 1
fi

prompt_directory=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
prompt_parent=$(cd -- "$(dirname -- "$prompt_file")" && pwd -P)
prompt_name=$(basename -- "$prompt_file")
if [[ $prompt_parent != "$prompt_directory" || $prompt_name != ghostty-pi-tab.prompt.* ]]; then
  printf 'Prompt file is outside the private Ghostty Pi Tab namespace: %s\n' "$prompt_file" >&2
  exit 1
fi

permissions=$(stat -f '%Lp' "$prompt_file")
if [[ $permissions != 600 ]]; then
  printf 'Prompt file must have mode 600, got %s: %s\n' "$permissions" "$prompt_file" >&2
  exit 1
fi

if ! command -v pi >/dev/null 2>&1; then
  printf 'pi is unavailable on PATH.\n' >&2
  exit 1
fi

cleanup() {
  rm -f -- "$prompt_file"
}
trap cleanup EXIT HUP INT TERM

pi "@$prompt_file"
