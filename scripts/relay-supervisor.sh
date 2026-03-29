#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run Claude first, then auto-handoff to OpenCode on limit.

Usage:
  ./scripts/relay-supervisor.sh --task "<task>" [options]

Required:
  --task            Task to execute with Claude first

Options:
  --bundle-dir      Bundle root directory (default: .handoff)
  --claude-model    Claude model alias/name
  --claude-agent    Claude agent name (default: relay)
  --opencode-model  OpenCode model (provider/model)
  --opencode-agent  OpenCode agent name (default: relay)
  --notes-file      Markdown notes file copied into bundle as NOTES.md
  --no-opencode     Do not auto-launch OpenCode after bundle creation
  --simulate-limit  Skip Claude call and force a limit-triggered handoff
  -h, --help        Show this help
EOF
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    printf "Missing value for %s\n" "$flag" >&2
    exit 1
  fi
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
bundle_script="$script_dir/create-handoff-bundle.sh"

task=""
bundle_root=".handoff"
claude_model=""
claude_agent="relay"
opencode_model=""
opencode_agent="relay"
notes_file=""
launch_opencode=1
simulate_limit=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      require_value "$1" "${2:-}"
      task="$2"
      shift 2
      ;;
    --bundle-dir)
      require_value "$1" "${2:-}"
      bundle_root="$2"
      shift 2
      ;;
    --claude-model)
      require_value "$1" "${2:-}"
      claude_model="$2"
      shift 2
      ;;
    --claude-agent)
      require_value "$1" "${2:-}"
      claude_agent="$2"
      shift 2
      ;;
    --opencode-model)
      require_value "$1" "${2:-}"
      opencode_model="$2"
      shift 2
      ;;
    --opencode-agent)
      require_value "$1" "${2:-}"
      opencode_agent="$2"
      shift 2
      ;;
    --notes-file)
      require_value "$1" "${2:-}"
      notes_file="$2"
      shift 2
      ;;
    --no-opencode)
      launch_opencode=0
      shift
      ;;
    --simulate-limit)
      simulate_limit=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf "Unknown argument: %s\n" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$task" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -x "$bundle_script" ]]; then
  printf "Bundle script missing or not executable: %s\n" "$bundle_script" >&2
  exit 1
fi

if [[ $simulate_limit -eq 0 ]] && ! command -v claude >/dev/null 2>&1; then
  printf "Claude CLI is required but was not found in PATH.\n" >&2
  exit 1
fi

if [[ $launch_opencode -eq 1 ]] && ! command -v opencode >/dev/null 2>&1; then
  printf "OpenCode CLI is required but was not found in PATH.\n" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

claude_output_file="$tmp_dir/claude-output.txt"
claude_invocation=""
claude_exit=0

detect_limit_reason() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").lower()
patterns = [
    (r"rate_limit_exceeded", "rate_limit_exceeded"),
    (r"usage\s+limit\s+reached", "usage_limit_reached"),
    (r"quota\s+exceeded", "quota_exceeded"),
    (r"http\s*429", "http_429"),
    (r"status\s*code\s*[:=]\s*429", "http_429"),
    (r"too\s+many\s+requests", "too_many_requests"),
]
for pattern, reason in patterns:
    if re.search(pattern, text):
        print(reason)
        break
PY
}

extract_bundle_path() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
match = re.search(r"Handoff bundle created at:\s*(.+)", text)
if match:
    print(match.group(1).strip())
PY
}

create_auto_notes() {
  local output_path="$1"
  local claude_log="$2"
  local exit_code="$3"
  local invocation="$4"
  CLAUDE_LOG="$claude_log" NOTES_PATH="$output_path" CLAUDE_EXIT_CODE="$exit_code" CLAUDE_INVOKE="$invocation" python3 - <<'PY'
import os
from pathlib import Path

log_path = Path(os.environ["CLAUDE_LOG"])
notes_path = Path(os.environ["NOTES_PATH"])
exit_code = os.environ["CLAUDE_EXIT_CODE"]
invocation = os.environ["CLAUDE_INVOKE"]

text = log_path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()
if len(lines) > 300:
    lines = ["[... truncated to last 300 lines ...]"] + lines[-300:]
trimmed = "\n".join(lines)

notes = "\n".join(
    [
        "# Claude Relay Notes",
        "",
        "## Invocation",
        "```bash",
        invocation,
        "```",
        "",
        "## Exit Code",
        str(exit_code),
        "",
        "## Captured Output",
        "```text",
        trimmed,
        "```",
        "",
    ]
)
notes_path.write_text(notes, encoding="utf-8")
PY
}

printf "Running Claude first...\n"

if [[ $simulate_limit -eq 1 ]]; then
  claude_invocation="claude -p --agent ${claude_agent} \"${task}\""
  printf "Simulated run: forcing limit detection without calling Claude.\n" > "$claude_output_file"
  printf "rate_limit_exceeded\n" >> "$claude_output_file"
  claude_exit=99
else
  claude_cmd=(claude -p)
  if [[ -n "$claude_agent" ]]; then
    claude_cmd+=(--agent "$claude_agent")
  fi
  if [[ -n "$claude_model" ]]; then
    claude_cmd+=(--model "$claude_model")
  fi
  claude_cmd+=("$task")

  claude_invocation="${claude_cmd[*]}"

  set +e
  "${claude_cmd[@]}" > "$claude_output_file" 2>&1
  claude_exit=$?
  set -e
fi

if [[ $claude_exit -eq 0 ]]; then
  printf "Claude completed successfully (no handoff needed).\n\n"
  cat "$claude_output_file"
  exit 0
fi

limit_reason="$(detect_limit_reason "$claude_output_file")"
if [[ -z "$limit_reason" && $simulate_limit -eq 1 ]]; then
  limit_reason="rate_limit_exceeded_simulated"
fi

if [[ -z "$limit_reason" ]]; then
  printf "Claude failed for a non-limit reason (exit %s).\n" "$claude_exit" >&2
  cat "$claude_output_file" >&2
  exit "$claude_exit"
fi

printf "Claude limit detected (%s). Preparing handoff bundle...\n" "$limit_reason"

final_notes_file="$notes_file"
if [[ -z "$final_notes_file" ]]; then
  final_notes_file="$tmp_dir/auto-notes.md"
  create_auto_notes "$final_notes_file" "$claude_output_file" "$claude_exit" "$claude_invocation"
fi

bundle_output_file="$tmp_dir/bundle-output.txt"
set +e
"$bundle_script" --task "$task" --reason "$limit_reason" --bundle-dir "$bundle_root" --notes-file "$final_notes_file" > "$bundle_output_file" 2>&1
bundle_exit=$?
set -e

if [[ $bundle_exit -ne 0 ]]; then
  printf "Failed to create handoff bundle.\n" >&2
  cat "$bundle_output_file" >&2
  exit "$bundle_exit"
fi

bundle_dir="$(extract_bundle_path "$bundle_output_file")"
if [[ -z "$bundle_dir" ]]; then
  printf "Bundle created but path could not be parsed.\n" >&2
  cat "$bundle_output_file" >&2
  exit 1
fi

if [[ "$bundle_dir" != /* ]]; then
  bundle_abs="$repo_root/$bundle_dir"
else
  bundle_abs="$bundle_dir"
fi

cp "$claude_output_file" "$bundle_abs/claude-output.txt"

BUNDLE_DIR="$bundle_abs" \
LIMIT_REASON="$limit_reason" \
CLAUDE_EXIT_CODE="$claude_exit" \
python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
summary = bundle_dir / "SUMMARY.md"
context = bundle_dir / "context.json"
reason = os.environ["LIMIT_REASON"]
exit_code = os.environ["CLAUDE_EXIT_CODE"]

summary.write_text(
    "\n".join(
        [
            "# Claude to OpenCode Handoff",
            "",
            "## Task",
            json.loads(context.read_text(encoding="utf-8"))["task"],
            "",
            "## Trigger",
            reason,
            "",
            "## Completed Work",
            "- Started execution with Claude Code.",
            f"- Stopped at limit trigger: {reason} (Claude exit {exit_code}).",
            "- Captured context, git state, and diffs for OpenCode continuation.",
            "",
            "## Remaining Work",
            "- Continue implementation in OpenCode from this bundle.",
            "- Validate behavior and run relevant tests before finalizing.",
            "",
            "## Risks or Open Questions",
            "- Confirm that any in-flight assumptions from Claude output remain valid.",
            "",
        ]
    ),
    encoding="utf-8",
)

payload = json.loads(context.read_text(encoding="utf-8"))
payload.setdefault("files", {})["claude_output"] = "claude-output.txt"
context.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

resume_prompt=$(cat <<EOF
Continue this task from handoff bundle \`$bundle_abs\`.

Read these files in order:
1. \`$bundle_abs/context.json\`
2. \`$bundle_abs/SUMMARY.md\`
3. \`$bundle_abs/NEXT_STEPS.md\`
4. \`$bundle_abs/working.diff\`
5. \`$bundle_abs/staged.diff\`

Then continue from the first unfinished step.
EOF
)

printf "\n## HANDOFF READY\n"
printf -- "- Bundle: %s\n" "$bundle_abs"
printf -- "- Trigger: %s\n" "$limit_reason"
printf -- "- Branch: %s@%s\n" "$(git rev-parse --abbrev-ref HEAD)" "$(git rev-parse --short HEAD)"
printf -- "- Completed: Claude ran until limit; bundle and context captured\n"
printf -- "- Remaining: OpenCode continuation + verification\n"
printf -- "- First OpenCode action: Read %s/context.json\n" "$bundle_abs"

if [[ $launch_opencode -eq 0 ]]; then
  printf "\nSkipping OpenCode launch (--no-opencode).\n"
  exit 0
fi

printf "\nLaunching OpenCode continuation...\n"
opencode_cmd=(opencode run --dir "$repo_root")
if [[ -n "$opencode_agent" ]]; then
  opencode_cmd+=(--agent "$opencode_agent")
fi
if [[ -n "$opencode_model" ]]; then
  opencode_cmd+=(--model "$opencode_model")
fi
opencode_cmd+=("$resume_prompt")

set +e
"${opencode_cmd[@]}"
opencode_exit=$?
set -e

if [[ $opencode_exit -ne 0 ]]; then
  printf "OpenCode launch failed with exit %s.\n" "$opencode_exit" >&2
  printf "Run this manually:\n" >&2
  printf "opencode run --dir \"%s\" --agent \"%s\" \"Continue this task from handoff bundle %s\"\n" "$repo_root" "$opencode_agent" "$bundle_abs" >&2
  exit "$opencode_exit"
fi
