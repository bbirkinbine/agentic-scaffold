#!/usr/bin/env bash
# Shared PreToolUse hook — refuse edits to the paths the contract protects.
#
# AGENTS.md → Don't-touch list names paths an agent must not change without
# asking. This hook makes the path entries mechanical: each line of
# .agentic/protected-paths (project-owned; one glob per line, # comments)
# is matched against the file an edit tool is about to touch, read from the
# payload on stdin: `tool_input.file_path` (Claude Code Edit/Write, Pi
# edit/write) or the `*** Add File:` / `*** Update File:` / `*** Delete
# File:` / `*** Move to:` lines of a Codex apply_patch. A match exits 2 with
# the reason on stderr, which the client feeds back to the model.
#
# Globs are bash patterns matched against the path relative to the project
# root: `*` crosses `/`, so `src/app/migrations/*` covers the whole tree
# under it; a line naming a directory, with or without a trailing `/`,
# protects everything beneath it. The list and this hook are not protected
# by default: an agent that edits the list to get past it is doing exactly
# what the Don't-touch rule forbids, and the reviewer's don't-touch check
# still reads the diff.
#
# Missing or empty list: allow. Extraction miss: allow. Path outside the
# project: allow. The hook must never block an edit over its own
# infrastructure. Needs only bash 3.2 and sed, like the other hooks.

set -euo pipefail

# Run from the project root (two levels above .agentic/hooks/).
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 0
root="$(pwd -P)"
LIST=.agentic/protected-paths
[[ -f "$LIST" ]] || exit 0

payload=""
[[ -t 0 ]] || payload="$(cat)"
[[ -n "$payload" ]] || exit 0

# Relative paths resolve against the client's working directory.
cwd="$(printf '%s' "$payload" \
  | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[[ -n "$cwd" ]] || cwd="$root"

patterns=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "$line" ]] || continue
  line="${line#./}"
  line="${line%/}"
  [[ -n "$line" ]] || continue
  patterns+=("$line")
done < "$LIST"
((${#patterns[@]})) || exit 0

# Root-relative form of a path that may not exist yet (Write creates files):
# normalized lexically, then its deepest existing ancestor is resolved
# physically so a symlinked prefix (macOS /var -> /private/var, a linked
# checkout) compares equal to the physical root. Prints nothing for a path
# outside the project.
relative_to_root() {
  local path="$1" part joined="" rest="" parts=() out=()
  [[ "$path" == /* ]] || path="$cwd/$path"
  IFS=/ read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in
      "" | .) ;;
      ..) ((${#out[@]})) && out=("${out[@]:0:${#out[@]}-1}") ;;
      *) out+=("$part") ;;
    esac
  done
  ((${#out[@]})) || return 0
  joined="/$(IFS=/; printf '%s' "${out[*]}")"
  while [[ ! -d "$joined" && "$joined" != / ]]; do
    rest="/$(basename "$joined")$rest"
    joined="$(dirname "$joined")"
  done
  joined="$(cd "$joined" 2>/dev/null && pwd -P)" || return 0
  [[ "$joined" == / ]] && joined=""
  joined="$joined$rest"
  [[ "$joined" == "$root"/* ]] || return 0
  printf '%s\n' "${joined#"$root"/}"
}

blocked=0
while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  rel="$(relative_to_root "$raw")"
  [[ -n "$rel" ]] || continue
  for pattern in "${patterns[@]}"; do
    # shellcheck disable=SC2053  # unquoted on purpose: the list holds globs
    if [[ "$rel" == $pattern || "$rel" == $pattern/* ]]; then
      cat >&2 <<MSG
BLOCKED by .agentic/hooks/protect-paths.sh
  path:    $rel
  pattern: $pattern  (.agentic/protected-paths)

This path is on the AGENTS.md Don't-touch list. Editing it is a scope
expansion: stop and ask the human. With their approval they remove or
comment out that line in .agentic/protected-paths, which is theirs to edit.
MSG
      blocked=1
      break
    fi
  done
done < <(
  printf '%s\n' "$payload" \
    | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  # apply_patch arrives as one JSON string, so its newlines are literal \n.
  printf '%s\n' "$payload" | awk '{ gsub(/\\n/, "\n"); print }' \
    | sed -En 's/^\*\*\* (Add File|Update File|Delete File|Move to): (.*)$/\2/p'
)

[[ "$blocked" == 0 ]] || exit 2
exit 0
