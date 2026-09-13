#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ask_opencode.sh <task> [options]
  -t, --task <text>       Task text (or pipe it on stdin)
  -w, --workspace <path>  Workspace directory (default: current directory)
  -f, --file <path>       Priority file or media path (repeatable)
      --session <id>      Resume a session
      --continue          Resume the most recent workspace session
      --model <name>      OpenCode provider/model
      --agent <name>      OpenCode agent
      --variant <name>    Provider-specific model variant
      --thinking          Include thinking blocks when supported
      --auto              Auto-approve permissions (use carefully)
  -o, --output <path>     Markdown output path
  -h, --help              Show this help
USAGE
}

fail() { echo "[ERROR] $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }
require_value() { [[ -n "${2:-}" ]] || fail "Missing value for $1"; }
trim() { awk 'BEGIN { RS=""; ORS="" } { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, ""); print }' <<<"$1"; }
absolute() {
  local base="$1" target="$2" parent
  [[ "$target" = /* ]] || target="$base/$target"
  if [[ -e "$target" ]]; then
    parent="$(cd "$(dirname "$target")" && pwd)"
    printf '%s/%s\n' "$parent" "$(basename "$target")"
  else printf '%s\n' "$target"; fi
}
redact() {
  sed -E -e 's/(Bearer )[A-Za-z0-9._~+\/=:-]+/\1[REDACTED]/g' \
    -e 's/(sk-[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+/\1...[REDACTED]/g' \
    -e 's/((api_key|api-key|access_token|refresh_token|secret)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/g'
}
progress() {
  local line="$1" type tool preview
  type="$(printf '%s' "$line" | jq -r '.type // ""' 2>/dev/null || true)"
  if [[ "$type" = tool || "$type" = tool_use ]]; then
    tool="$(printf '%s' "$line" | jq -r '.part.tool // .tool // .name // "tool"' 2>/dev/null || true)"
    [[ -n "$tool" ]] && echo "[opencode] tool: $tool" >&2
  else
    preview="$(printf '%s' "$line" | jq -r '.part.text // .text // .message.content // empty' 2>/dev/null | awk 'NF { print; exit }' | cut -c1-140 || true)"
    [[ -n "$preview" ]] && echo "[opencode] $preview" >&2
  fi
}

workspace="$PWD"; task=""; model=""; agent=""; variant=""; session=""; output=""
continue_session=0; thinking=0; auto=0; files=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--task) require_value "$1" "${2:-}"; task="$2"; shift 2;;
    -w|--workspace) require_value "$1" "${2:-}"; workspace="$2"; shift 2;;
    -f|--file) require_value "$1" "${2:-}"; files+=("$2"); shift 2;;
    --session) require_value "$1" "${2:-}"; session="$2"; shift 2;;
    --continue) continue_session=1; shift;;
    --model) require_value "$1" "${2:-}"; model="$2"; shift 2;;
    --agent) require_value "$1" "${2:-}"; agent="$2"; shift 2;;
    --variant) require_value "$1" "${2:-}"; variant="$2"; shift 2;;
    --thinking) thinking=1; shift;;
    --auto) auto=1; shift;;
    -o|--output) require_value "$1" "${2:-}"; output="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    -*) echo "[ERROR] Unknown option: $1" >&2; usage >&2; exit 1;;
    *) [[ -z "$task" ]] || fail "Unexpected argument: $1"; task="$1"; shift;;
  esac
done

require_cmd opencode; require_cmd jq
[[ -d "$workspace" ]] || fail "Workspace does not exist: $workspace"
workspace="$(cd "$workspace" && pwd)"
if [[ -z "$task" && ! -t 0 ]]; then task="$(cat)"; fi
task="$(trim "$task")"; [[ -n "$task" ]] || fail "Request text is empty"

prompt="$task"
if (( ${#files[@]} )); then
  prompt+=$'\n\nPriority files or media (inspect these first):'
  for file in "${files[@]}"; do
    path="$(absolute "$workspace" "$file")"; exists=missing; [[ -e "$path" ]] && exists=exists
    prompt+=$'\n- '"$path ($exists)"
  done
fi
if [[ -z "$output" ]]; then
  skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  output="$skill_dir/.runtime/$(date -u +"%Y%m%d-%H%M%S")-$$.md"
elif [[ "$output" != /* ]]; then output="$workspace/$output"; fi
mkdir -p "$(dirname "$output")"; output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"

cmd=(opencode run)
[[ -n "$session" ]] && cmd+=(--session "$session")
(( continue_session )) && cmd+=(--continue)
[[ -n "$model" ]] && cmd+=(--model "$model")
[[ -n "$agent" ]] && cmd+=(--agent "$agent")
[[ -n "$variant" ]] && cmd+=(--variant "$variant")
(( thinking )) && cmd+=(--thinking)
(( auto )) && cmd+=(--auto)
for file in "${files[@]}"; do cmd+=(--file "$(absolute "$workspace" "$file")"); done
cmd+=(--format json "$prompt")

json_file="$(mktemp)"; stderr_file="$(mktemp)"; trap 'rm -f "$json_file" "$stderr_file"' EXIT
start=$SECONDS; status=0
set +e
(cd "$workspace" && "${cmd[@]}" 2>"$stderr_file") | while IFS= read -r line; do
  line="${line//$'\r'/}"; [[ -n "$line" ]] || continue
  if printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "$line" >>"$json_file"; progress "$line"
  else echo "[opencode] Ignored non-JSON output" >&2; fi
done
status=${PIPESTATUS[0]}; set -e; elapsed=$((SECONDS-start))
if (( status != 0 )); then
  echo "[ERROR] OpenCode command failed (exit $status)" >&2
  [[ -s "$stderr_file" ]] && tail -n 40 "$stderr_file" | redact >&2
  exit "$status"
fi
[[ -s "$json_file" ]] || fail "OpenCode returned no JSON events; check providers/auth"

session_out="$(jq -rs '[.[] | (.sessionID // .session_id // .session.id // empty) | select(type == "string" and length > 0)] | last // ""' "$json_file" 2>/dev/null)"
[[ -n "$session_out" ]] || session_out="$session"
summary="$(jq -rs '[.[] | (.part.text // .text // .message.content // empty) | select(type == "string" and length > 0)] | join("")' "$json_file" 2>/dev/null)"
[[ -n "$summary" ]] || summary="(OpenCode completed without a final text event.)"
tools="$(jq -rs '[.[] | select((.type // "") == "tool" or (.type // "") == "tool_use") | (.part.tool // .tool // .name // "tool")] | group_by(.) | map("- `" + .[0] + "` ×" + (length | tostring)) | .[]' "$json_file" 2>/dev/null)"
{
  printf '## Summary\n\n%s\n\n' "$summary"
  [[ -n "$tools" ]] && printf '## Tools used\n\n%s\n\n' "$tools"
  printf -- '---\nelapsed %ss · %s events\n' "$elapsed" "$(wc -l <"$json_file" | tr -d ' ')"
} >"$output"
[[ -n "$session_out" ]] && echo "session_id=$session_out"
echo "output_path=$output"; echo "elapsed=${elapsed}s"

