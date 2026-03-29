#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Create a Claude-to-OpenCode handoff bundle.

Usage:
  ./scripts/create-handoff-bundle.sh --task "<task>" --reason "<limit reason>" [options]

Required:
  --task          Human-readable task title
  --reason        Why handoff happened (example: rate_limit_exceeded)

Optional:
  --bundle-dir    Root directory for bundles (default: .handoff)
  --notes-file    Markdown notes file to copy as NOTES.md
  --source-model  Source model name (default: claude-code)
  -h, --help      Show this help
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

task=""
reason=""
bundle_root=".handoff"
notes_file=""
source_model="claude-code"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      require_value "$1" "${2:-}"
      task="$2"
      shift 2
      ;;
    --reason)
      require_value "$1" "${2:-}"
      reason="$2"
      shift 2
      ;;
    --bundle-dir)
      require_value "$1" "${2:-}"
      bundle_root="$2"
      shift 2
      ;;
    --notes-file)
      require_value "$1" "${2:-}"
      notes_file="$2"
      shift 2
      ;;
    --source-model)
      require_value "$1" "${2:-}"
      source_model="$2"
      shift 2
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

if [[ -z "$task" || -z "$reason" ]]; then
  usage >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "This command must run inside a git repository.\n" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf "python3 is required to create context.json.\n" >&2
  exit 1
fi

timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

slug="$(printf '%s' "$task" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
while [[ "$slug" == -* ]]; do
  slug="${slug#-}"
done
while [[ "$slug" == *- ]]; do
  slug="${slug%-}"
done
if [[ -z "$slug" ]]; then
  slug="task"
fi

bundle_dir="${bundle_root}/${timestamp}-${slug}"
mkdir -p "$bundle_dir"

branch="$(git rev-parse --abbrev-ref HEAD)"
head_sha="$(git rev-parse HEAD)"
short_sha="$(git rev-parse --short HEAD)"
remote_url="$(git remote get-url origin 2>/dev/null || true)"

git status --short --branch > "$bundle_dir/git-status.txt"
git diff > "$bundle_dir/working.diff"
git diff --cached > "$bundle_dir/staged.diff"
git log --oneline -n 30 > "$bundle_dir/recent-commits.txt"

if [[ -n "$notes_file" ]]; then
  if [[ ! -f "$notes_file" ]]; then
    printf "Notes file not found: %s\n" "$notes_file" >&2
    exit 1
  fi

  cp "$notes_file" "$bundle_dir/NOTES.md"
fi

cat > "$bundle_dir/SUMMARY.md" <<EOF
# Claude to OpenCode Handoff

## Task
$task

## Trigger
$reason

## Completed Work
- Fill this in before handing off.

## Remaining Work
- Fill this in before handing off.

## Risks or Open Questions
- Fill this in if needed.
EOF

cat > "$bundle_dir/NEXT_STEPS.md" <<'EOF'
# Next Steps for OpenCode

1. Read `context.json`, `SUMMARY.md`, and `git-status.txt`.
2. Review `working.diff` and `staged.diff`.
3. Continue from the first unfinished item in `SUMMARY.md`.
4. Run relevant verification commands before finalizing.
EOF

cat > "$bundle_dir/RESUME_PROMPT.md" <<'EOF'
Continue this task from the provided handoff bundle directory.

Required reading order:
1. context.json
2. SUMMARY.md
3. NEXT_STEPS.md
4. working.diff
5. staged.diff

Then continue implementation from the first unfinished step while preserving existing constraints.
EOF

HANDOFF_TASK="$task" \
HANDOFF_REASON="$reason" \
HANDOFF_SOURCE_MODEL="$source_model" \
HANDOFF_CREATED_AT="$created_at" \
HANDOFF_BRANCH="$branch" \
HANDOFF_HEAD_SHA="$head_sha" \
HANDOFF_SHORT_SHA="$short_sha" \
HANDOFF_REMOTE_URL="$remote_url" \
HANDOFF_BUNDLE_DIR="$bundle_dir" \
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "schema_version": "1.0",
    "created_at": os.environ["HANDOFF_CREATED_AT"],
    "task": os.environ["HANDOFF_TASK"],
    "trigger": os.environ["HANDOFF_REASON"],
    "source_model": os.environ["HANDOFF_SOURCE_MODEL"],
    "branch": os.environ["HANDOFF_BRANCH"],
    "head_sha": os.environ["HANDOFF_HEAD_SHA"],
    "head_short_sha": os.environ["HANDOFF_SHORT_SHA"],
    "remote_url": os.environ["HANDOFF_REMOTE_URL"],
    "files": {
        "summary": "SUMMARY.md",
        "next_steps": "NEXT_STEPS.md",
        "git_status": "git-status.txt",
        "working_diff": "working.diff",
        "staged_diff": "staged.diff",
        "recent_commits": "recent-commits.txt",
        "resume_prompt": "RESUME_PROMPT.md",
        "notes": "NOTES.md"
    }
}

output_path = Path(os.environ["HANDOFF_BUNDLE_DIR"]) / "context.json"
output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

printf "Handoff bundle created at: %s\n" "$bundle_dir"
printf "Next steps:\n"
printf "  1) Fill in %s/SUMMARY.md\n" "$bundle_dir"
printf "  2) Share %s/RESUME_PROMPT.md with OpenCode\n" "$bundle_dir"
