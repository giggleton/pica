#!/usr/bin/env bash
# The commit gate: hard-blocks `git commit` until the review and docs passes are recorded for the
# EXACT current working tree, and until every area whose code changed has had its rules file
# looked at.
#
# Why this exists: CLAUDE.md requires the elixir-code-review and docs-sync skills before reporting
# done on any change touching `test/` or a GenServer — and that rule gets skipped
# under wrap-up pressure. A memory is advisory; this hook is enforced by the harness, the same
# reasoning that gives the repo `mix quality` instead of "keep the suite green" as discipline.
#
# The rules, checked in this order:
#   1. WAIVER GATE — a new lint/security waiver must carry its `# why:` / `# instead of:` lines
#      (waiver-gate.sh documents the fields and enforces them at authoring time; this is the
#      backstop for an edit made through Bash or sed).
#   2. PAIRED PATHS — every `.claude/rules/<area>.md` declares in `paths:` the code it describes.
#      A diff that changes code matching an area's globs without changing that area's rules file
#      is denied unless the docs mark is current, i.e. docs-sync ran against this exact diff and
#      decided the rules needed nothing. Only code changes trigger it: `.md` files and anything
#      under `.claude/` are documentation, so a docs-only commit never has to justify itself. This
#      is the enforced form of docs-sync's "docs update in the same change".
#   3. GATED PATHS — a diff touching test/**, or a `use GenServer` module
#      needs both the review and the docs mark.
#
# Protocol:
#   * `check` — the PreToolUse(Bash) hook entry point. Reads the tool-call JSON on stdin; ignores
#     anything that isn't a `git commit`.
#   * `mark review` / `mark docs` — the skills' final step (and ONLY theirs — see below) records
#     the pass. Marks live under .git/, so they can never be committed or shared, and are per
#     checkout.
#
# A review or docs mark is a hash over EVERY changed path and its content (staged, unstaged,
# untracked, deletions included), so editing any file after a pass makes the mark stale on
# purpose: a follow-up tweak owes its own pass ("per change, not per session"). Run `mix format`
# before marking, so the recorded state is the one quality's format step will keep.
#
# Honesty note: nothing can physically stop the agent running `mark` without doing the work — it
# executes the skills too. The gate's value is that the ONLY documented path to a mark is the final
# step of the skill itself, so skipping becomes an explicit act instead of a slide.
#
# Glob matching for rule 2 uses bash patterns, where `*` also crosses `/` and braces are not
# expanded — slightly more permissive than the harness's globs, which errs toward asking for the
# docs pass. Avoid braces in `paths:` globs; `mix tack.rules_check` keeps the globs honest.
#
# Requires `jq` and `git` on PATH.

marks_dir="$(git rev-parse --git-dir)/claude-skill-marks"
hooks_dir="$(dirname "${BASH_SOURCE[0]}")"
rules_dir=".claude/rules"

# Every changed path (staged, unstaged, untracked), rename targets resolved.
changed_paths() {
  git status --porcelain=v1 -uall | sed -e 's/^...//' -e 's/.* -> //'
}

# The subset rule 3 cares about — mirrors CLAUDE.md's elixir-code-review trigger.
gated_paths() {
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
      test/*)
        printf '%s\n' "$path"
        ;;
      lib/*.ex)
        if [ -f "$path" ] && grep -q "use GenServer" "$path"; then
          printf '%s\n' "$path"
        fi
        ;;
    esac
  done
}

# Content hash of a path set: paths plus each file's blob hash (deletions included), so any edit to
# any file in the set after a pass invalidates the mark.
state_hash() {
  {
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      if [ -f "$path" ]; then
        printf '%s %s\n' "$path" "$(git hash-object "$path")"
      else
        printf '%s deleted\n' "$path"
      fi
    done
  } | sha256sum | cut -d' ' -f1
}

# The `paths:` globs declared in a rules file's frontmatter, one per line.
rules_globs() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    /^paths:/ { in_paths = 1; next }
    in_paths && /^[[:space:]]+-[[:space:]]/ { line = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", line); gsub(/"/, "", line); print line; next }
    in_paths { in_paths = 0 }
  ' "$1"
}

# Rule 2: for each rules file whose globs match a changed CODE path, and which did not itself
# change, print "<rules file> (<first matching path>)".
areas_missing_docs() {
  local changed="$1" rules_file glob path
  for rules_file in "$rules_dir"/*.md; do
    [ -f "$rules_file" ] || continue
    if printf '%s\n' "$changed" | grep -qxF "$rules_file"; then continue; fi
    while IFS= read -r glob; do
      [ -z "$glob" ] && continue
      while IFS= read -r path; do
        [ -z "$path" ] && continue
        case "$path" in
          *.md | .claude/*) continue ;;
        esac
        # shellcheck disable=SC2254 # the glob is meant to be a pattern
        if [[ "$path" == $glob ]]; then
          printf '%s (%s)\n' "$rules_file" "$path"
          continue 3
        fi
      done <<<"$changed"
    done < <(rules_globs "$rules_file")
  done
}

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

mark_status() {
  local mark_file="$1" current="$2"
  if [ ! -f "$mark_file" ]; then
    echo "missing"
  elif [ "$(cat "$mark_file")" = "$current" ]; then
    echo "ok"
  else
    echo "stale"
  fi
}

command="${1:-check}"

case "$command" in
  mark)
    kind="${2:?usage: commit-gate.sh mark review|docs}"
    case "$kind" in
      review | docs)
        mkdir -p "$marks_dir"
        changed_paths | sort -u | state_hash >"$marks_dir/$kind"
        echo "marked $kind for the current working tree"
        ;;
      *) echo "unknown mark kind: $kind" >&2 && exit 1 ;;
    esac
    ;;

  check)
    input="$(cat)"
    tool_command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

    # Only gate actual commits; a compound command like `git add -A && git commit` still
    # contains the literal substring. Everything else passes untouched.
    case "$tool_command" in
      *"git commit"*) ;;
      *) exit 0 ;;
    esac

    changed="$(changed_paths | sort -u)"
    [ -z "$changed" ] && exit 0

    # Rule 1.
    waivers="$(bash "$hooks_dir/waiver-gate.sh" diff || true)"
    if [ -n "$waivers" ]; then
      deny "WAIVER GATE: this diff adds a lint/security waiver without the two lines that must sit above it — '# why: <what the code needs and the invariant keeping it safe>' and '# instead of: <alternative> — rejected because <reason>'. First ask whether the code needs the flagged construct at all. Offending lines:
$waivers"
    fi

    current="$(printf '%s\n' "$changed" | state_hash)"
    review_state="$(mark_status "$marks_dir/review" "$current")"
    docs_state="$(mark_status "$marks_dir/docs" "$current")"

    # Rule 2.
    unpaired="$(areas_missing_docs "$changed")"
    if [ -n "$unpaired" ] && [ "$docs_state" != "ok" ]; then
      deny "PAIRED PATHS: this diff changes code in an area whose rules file did not change (docs mark: $docs_state). Either update the area's .claude/rules file in this change, or run the docs-sync skill for THIS diff — its final step records the docs mark, which is how you say the rules needed nothing. Areas:
$unpaired"
    fi

    # Rule 3.
    gated="$(printf '%s\n' "$changed" | gated_paths | sort -u)"
    [ -z "$gated" ] && exit 0

    if [ "$review_state" = "ok" ] && [ "$docs_state" = "ok" ]; then
      exit 0
    fi

    deny "COMMIT GATE: this diff touches review-gated paths ('test/' or a GenServer) and the skill passes are not recorded for its current state (review: $review_state, docs: $docs_state). Run the elixir-code-review skill, then the docs-sync skill, for THIS diff — each ends by running 'bash .claude/hooks/commit-gate.sh mark review' / 'mark docs'. A stale mark means a file changed after the pass: run 'mix format' and re-run the skill for the delta. Gated paths:
$gated"
    ;;

  *)
    echo "usage: commit-gate.sh check|mark review|docs" >&2
    exit 1
    ;;
esac
