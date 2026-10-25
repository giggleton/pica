#!/usr/bin/env bash
# The waiver gate: a new lint or security suppression — or a widened architectural boundary — is a
# decision the user makes, not one the agent slides into while wrapping up.
#
# Why this exists: the day a `System.cmd` call arrives with a credo waiver and a checkable
# "why it is safe" comment, passes the review skill, and is replaced an hour later by
# `Path.wildcard` when the user asks whether the shell-out was needed at all. The review asked
# whether the waiver was justified; nobody asked whether the flagged construct was necessary.
# Prose in a skill did not prompt that question. A hook does.
#
# Two entry points:
#   * `edit` — the PreToolUse(Edit|Write) hook. Reads the tool call on stdin. When an edit ADDS a
#     waiver marker to a code file (`@sobelow_skip [...]`, `credo:disable-for-*`, a hex.audit
#     `ignore_advisories`/`ignore_retirements` entry), it is DENIED until the edit also carries, above
#     each waiver, the two fields that make the decision checkable:
#         # why: <what the code needs that trips the tool, and the invariant that keeps it safe>
#         # instead of: <the alternative considered> — rejected because <reason>
#     With both fields present the hook answers "ask": the harness shows the user the edit and this
#     reason, and the user decides. A headless session turns "ask" into "deny".
#   * `diff` — the commit-gate backstop (called from commit-gate.sh). Scans every changed code file
#     for an added waiver line without both fields in the eight lines above it, so an edit made
#     through Bash/sed cannot bypass the Edit hook. Prints one violation per line; exits 1 if any.
#
# BOUNDARY WIDENING IS DIFFERENT, and deliberately harsher than the waiver rule above: no comment
# satisfies it, and the Edit hook always DENIES so the widening has to be described to the user in
# plain language before anything else happens. See boundary_check/3 for why the gentler designs
# failed. The commit backstop then blocks until `approve-widening` records the user's answer,
# hashed against those exact declarations so a later widening cannot ride along on an earlier yes.
#
#   * `approve-widening` — run ONLY immediately after the user has been shown a widening and has
#     said to proceed. Nothing physically prevents it being run otherwise, exactly as with
#     commit-gate.sh's `mark` commands; the value is that the documented path runs through the
#     conversation the deny forces, so skipping is an explicit act rather than a slide.
#
# Fields rather than free prose because a field is checkable by grep and a paragraph is not, and
# because writing "instead of: X — rejected because Y" is what makes a weak rejection visible in the
# diff. `register_attribute(..., :sobelow_skip, ...)` is boilerplate, not a waiver, and is ignored,
# as is a marker quoted inside a `"""` heredoc — see strip_doc_lines.
set -euo pipefail

marker_re='@sobelow_skip[[:space:]]*[[]|credo:disable-for|ignore_advisories|ignore_retirements'
why_re='#[[:space:]]*why:'
instead_re='#[[:space:]]*instead of:'
lookback=8

code_file() {
  case "$1" in
    *.ex | *.exs | .sobelow-conf | */.sobelow-conf) return 0 ;;
    *) return 1 ;;
  esac
}

# Waiver lines in a text, boilerplate excluded. `grep` exits 1 on no match, and under
# `pipefail` + `set -e` that would kill the script at the caller's assignment, so a miss is
# caught here and reported as zero.
# Blank the body of every `"""` heredoc, so a marker *quoted* in a `@moduledoc`/`@doc` is not
# mistaken for one. This harness documents waivers in prose — the invariant that keeps a waiver
# safe is stated in a moduledoc, and `elixir-code-review/references/suppressions.md` holds that
# up as the pattern — so without this a file explaining a waiver reads as a file adding one:
# exactly the failure a naive boundary scanner has, unable to tell a declaration from a sentence
# about one. Lines are blanked rather than dropped so line numbers survive.
strip_doc_lines() {
  awk '{
    if (in_doc) print ""; else print
    if ((split($0, doc_parts, /"""/) - 1) % 2 == 1) in_doc = !in_doc
  }'
}

count_markers() {
  local count
  count=$(printf '%s\n' "$1" | strip_doc_lines | grep -E "$marker_re" | grep -v 'register_attribute' | wc -l) || true
  printf '%s' "${count:-0}" | tr -d ' '
}

# Complete `why` + `instead of` pairs in a text (the smaller of the two counts).
count_pairs() {
  local whys insteads
  whys=$(printf '%s\n' "$1" | grep -E -c "$why_re" || true)
  insteads=$(printf '%s\n' "$1" | grep -E -c "$instead_re" || true)
  if [ "${whys:-0}" -lt "${insteads:-0}" ]; then echo "${whys:-0}"; else echo "${insteads:-0}"; fi
}

decide() {
  local decision="$1" reason="$2"
  jq -n --arg decision "$decision" --arg reason "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}'
  exit 0
}

# A boundary grant is the same kind of decision as a lint waiver, and fails the same way: widening
# `deps:` or `exports:` to silence a forbidden-reference warning turns the architecture check into
# theatre, and unlike a too-narrow declaration it compiles in silence. The question the hook exists
# to force is "did you widen the declaration, or fix the call?" — almost always the latter.
#
# `check: [in/out/apps/aliases]`, `dirty_xrefs:` and `top_level?:` are NOT counted here; they are
# pinned by the boundary declarations test against a sanctioned list, which catches
# them on a first write as well as an edit.
#
# The count is a permission score over a file's declaration lines, built so that every narrowing
# reads as a decrease and every widening as an increase:
#   * each module named in a `deps: [...]` or `exports: [...]` list scores 1;
#   * `exports: :all` scores 1000 — maximal, since it exports everything there is;
#   * `exports: {:all, except: [A, B]}` scores 999 minus the exclusions, so adding an exclusion
#     narrows and removing one widens, while any `{:all, …}` still scores below a bare `:all`.
# Only the declaration itself is scored, never prose that happens to quote one — see
# boundary_declaration.
#
# The score is a proxy, and it is wrong in one known direction: `exports: :all` scores as
# maximal wherever it appears, but on a boundary nested inside another it makes every module
# unreachable from outside the parent, so replacing it with an explicit list reads as a large
# widening when it is a narrowing. Telling the two apart needs the boundary's place in the graph,
# which this script does not parse — so boundary_caveats says so in the deny message rather than
# pretending the number ranks the change.
#
# It is blind in a second direction: deleting a whole declaration. A boundary exporting only its
# root scores 0, and so does a file with no declaration at all — see boundary_count.
boundary_grants() {
  boundary_declaration "$1" | awk '
    {
      decl = $0
      line = decl
      while (match(line, /exports:[[:space:]]*:all/)) {
        total += 1000; line = substr(line, RSTART + RLENGTH)
      }
      line = decl
      while (match(line, /exports:[[:space:]]*\{:all/)) {
        total += 999; line = substr(line, RSTART + RLENGTH)
        if (match(line, /except:[[:space:]]*\[[^]]*\]/)) {
          s = substr(line, RSTART, RLENGTH)
          sub(/^except:[[:space:]]*\[/, "", s); sub(/\]$/, "", s); gsub(/[[:space:]]/, "", s)
          if (s != "") total -= split(s, x, ",")
        }
      }
      line = decl
      while (match(line, /(deps|exports):[[:space:]]*\[[^]]*\]/)) {
        s = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        sub(/^[a-z_]+:[[:space:]]*\[/, "", s); sub(/\]$/, "", s); gsub(/[[:space:]]/, "", s)
        if (s != "") total += split(s, parts, ",")
      }
      print total + 0
    }'
}

# Every `use Boundary` declaration in a text, flattened onto one line (several declarations join
# into one). A declaration runs from a line whose first token is `use Boundary` until its brackets
# balance, so a multi-line declaration is read whole while a moduledoc explaining `exports: :all`,
# or a test matching on it, contributes nothing. Both of those exist in this repo and both were
# miscounted by an earlier scorer that scanned from the first mention onward. Always prints one
# line, empty when there is no declaration, so the readers below see input either way.
boundary_declaration() {
  printf '%s\n' "$1" | awk '
    {
      line = $0; sub(/^[[:space:]]+/, "", line)
      if (!collecting) { if (line !~ /^use Boundary/) next; collecting = 1; depth = 0 }
      decl = decl " " line
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "[" || c == "{") depth++
        else if (c == "]" || c == "}") depth--
      }
      # A declaration ends where its brackets balance AND the line stops running on. The comma
      # matters on its own: once an export list grows past the line limit `mix format` rewrites the
      # declaration as `use Boundary,` with the options below it, and that first line opens no
      # bracket at all. A depth-only rule closes there and reads nothing but "use Boundary,", so
      # every multi-line declaration scores zero and the gate goes blind to exactly the ones that
      # got long enough to be worth watching. A trailing
      # colon runs on for the same reason one level down: `mix format` puts a long value on the
      # line below its key, so an umbrella may read `exports:` alone and then `{:all,` — and a
      # depth-only scorer gives it 0, so shortening its `except:` list widens nothing.
      if (depth <= 0 && line !~ /[,:]$/) { collecting = 0 }
    }
    END { print decl }'
}

# The options the score does not read — `type:`, `top_level?:`, `check:` and `dirty_xrefs:` — one
# per line, sorted, as written in the declaration. The boundary declarations test
# pins them, which catches a first write as well as an edit; but a widening that also sheds one
# should be shown whole, or a rename that also sheds `top_level?: true` reads as
# pure widening. Listed rather than weighed, because they point both ways: dropping `type: :strict`
# loosens a core, while dropping a read model's `top_level?:` would drop a check it adds.
boundary_options() {
  boundary_declaration "$1" | awk '
    {
      line = $0
      while (match(line, /(type:[[:space:]]*:[a-z_]+|top_level\?:[[:space:]]*[a-z]+|(check|dirty_xrefs):[[:space:]]*\[[^]]*\])/)) {
        print substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }' | sort
}

# The paragraph a widening's deny message carries after the score, so the reader sees what the
# number leaves out: the unscored options that changed, whether `exports: :all` makes the score
# unreliable, and whether the file had no declaration to compare against. Empty when none apply.
boundary_caveats() {
  local old="$1" new="$2" removed added
  removed="$(comm -23 <(boundary_options "$old") <(boundary_options "$new") | paste -sd ',' - | sed 's/,/, /g')"
  added="$(comm -13 <(boundary_options "$old") <(boundary_options "$new") | paste -sd ',' - | sed 's/,/, /g')"
  if [ -n "$removed$added" ]; then
    printf '\n\nThe score does not count these options, and this change also touches them — include them in what you tell the user: removed [%s], added [%s].' "$removed" "$added"
  fi
  if boundary_declaration "$old"$'\n'"$new" | grep -Eq 'exports:[[:space:]]*:all'; then
    printf '\n\nThe number may be wrong here: `exports: :all` scores as maximal wherever it appears, but on a boundary nested inside another it makes every module unreachable from outside the parent, so replacing it with an explicit list reads as a large widening when it is a narrowing. Say which this is from where the boundary sits, not from the score.'
  fi
  case "$old" in
    *"use Boundary"*) ;;
    *) printf '\n\nThere was no declaration to compare against, so every grant counts as new. If this file is being moved rather than created, `git mv` it first: the commit check then scores it against its old declaration.' ;;
  esac
}

# Which boundary each `classify_to:` in a file names. A mix task belongs to no architectural tier,
# so it is assigned to one by hand — and MOVING it between boundaries changes what it may call,
# which is a grant even though it is not a `deps:`/`exports:` entry and has no direction a score
# could rank. A score that reads only `deps:` and `exports:` is blind to it: a task moved from the
# umbrella into a read-model boundary gains the right to call that whole namespace, and
# nothing stops it. Any *change* to a target is treated as needing the user, since "more" and
# "less" are not comparable here — with the one exception without_own_protocol_classifications
# describes.
boundary_classifications() {
  boundary_declaration "$(without_own_protocol_classifications "$1")" | awk '
    {
      decl = $0
      while (match(decl, /classify_to:[[:space:]]*[A-Za-z0-9_.]+/)) {
        s = substr(decl, RSTART, RLENGTH)
        decl = substr(decl, RSTART + RLENGTH)
        sub(/^classify_to:[[:space:]]*/, "", s)
        out = out " " s
      }
      print out
    }'
}

# The text with each `classify_to:` that names the protocol of the `defimpl` it opens blanked out,
# so boundary_classifications does not read it as a move. Boundary does not check what a protocol
# implementation calls until the implementation is classified (`unclassified_protocol_impl?` in
# its checker), so classifying a `defimpl` into the boundary of the protocol it implements only
# ever narrows: the impl's calls go from unchecked to held to that boundary's `deps:`. It has one
# right answer, so stopping it would only stop every new implementation. Leaving one out, or removing it, compiles
# in silence and is not seen here either: the boundary declarations test fails on any protocol
# implementation not classified into its protocol's boundary. Recognised in one shape only — the
# declaration is the line straight after the `defimpl` line and names the protocol exactly as that
# line writes it — so anything else still reads as a move and stops.
without_own_protocol_classifications() {
  printf '%s\n' "$1" | awk '
    {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if (protocol != "" && line ~ /^use Boundary,[[:space:]]*classify_to:[[:space:]]*[A-Za-z0-9_.]+$/) {
        target = line; sub(/^use Boundary,[[:space:]]*classify_to:[[:space:]]*/, "", target)
        if (target == protocol) { protocol = ""; print ""; next }
      }
      protocol = ""
      if (line ~ /^defimpl[[:space:]]+[A-Za-z0-9_.]+[[:space:]]*,/) {
        protocol = line; sub(/^defimpl[[:space:]]+/, "", protocol); sub(/[[:space:]]*,.*$/, "", protocol)
      }
      print
    }'
}

# How many `use Boundary` declarations a text holds, docstrings excluded (strip_doc_lines), so a
# moduledoc showing one is not counted. Removing a declaration is a widening the permission score
# cannot see: `use Boundary, exports: []` scores 0, and so does no declaration at all, yet deleting
# it folds the boundary's modules into its parent, where every module may call what the declaration
# kept private. Found in Giggly by mutation testing: a mutant deleting a domain's declaration
# failed no test, compiled clean, and passed this hook, which read it as 0 → 0.
boundary_count() {
  printf '%s\n' "$1" | strip_doc_lines | awk '
    { line = $0; sub(/^[[:space:]]+/, "", line); if (line ~ /^use Boundary([,[:space:]]|$)/) count++ }
    END { print count + 0 }'
}

# Only files the boundary compiler actually reads — `elixirc_paths`, i.e. `.ex` under lib/ and
# test/support. A `use Boundary` in a `.exs` file is inert by construction: ExUnit loads those at
# runtime and the compiler never sees them. This is not a convenience carve-out; scanning them is
# simply wrong: the boundary declarations test's fixtures are declarations inside heredocs.
compiled_source() {
  case "$1" in
    *.ex) return 0 ;;
    *) return 1 ;;
  esac
}

boundary_check() {
  local path="$1" old="$2" new="$3" before after markers
  compiled_source "$path" || return 0
  case "$new$old" in *"use Boundary"*) ;; *) return 0 ;; esac

  if [ "$(boundary_classifications "$old")" != "$(boundary_classifications "$new")" ]; then
    decide deny "BOUNDARY GATE: this edit changes a \`classify_to:\` target in $path, moving a module from one boundary into another. That changes what it is allowed to call, so it is a grant like any other — and one the permission score cannot rank, since neither direction is obviously 'more'.

Stop and tell the user in plain language: which module moves, out of which boundary and into which, and what it can call there that it could not before. Then let them decide."
  fi

  if [ "$(boundary_count "$new")" -lt "$(boundary_count "$old")" ]; then
    decide deny "BOUNDARY GATE: this edit removes a \`use Boundary\` declaration from $path. That folds the boundary's modules into its parent, where every module may call what the declaration kept private — a widening the permission score cannot see, since a boundary exporting only its root scores 0 and so does no declaration at all.

This is a hard stop, as for any widening. Do NOT edit this hook to get past it.

Stop and tell the user in plain language: which boundary goes, which modules lose its protection, and what can now call them. If those modules are being deleted along with it, say so — that widens nothing. Then let them decide."
  fi

  before="$(boundary_grants "$old")"
  after="$(boundary_grants "$new")"
  [ "$after" -le "$before" ] && return 0

  markers="$(printf '%s\n' "$new" | grep -E 'use Boundary|^[[:space:]]*(deps|exports):' | sed 's/^[[:space:]]*//' | head -3 | paste -sd '|' - || true)"

  # ALWAYS deny, never "ask", and never satisfiable by a comment. Both of those were tried in the
  # same afternoon and both failed the same way. "ask" is waved through by the session's permission
  # mode, so the first widenings reach nobody. And the `# why:` field
  # was the agent writing a justification, satisfying its own rule with it, and approving it — a
  # control with no second party in it, which the user named as soon as they saw it.
  #
  # Deny is the only outcome a permission mode cannot auto-approve. It forces the explanation to
  # happen in conversation, in plain language, with the person who actually decides. That costs one
  # interruption per widening. That interruption IS the feature.
  decide deny "BOUNDARY GATE: this edit widens a boundary grant in $path (permission score $before → $after), so more of the codebase becomes reachable across an architectural seam.

This is a hard stop, not an approval prompt — an approval prompt gets auto-accepted and reaches no one. Do NOT add a comment to satisfy it, and do NOT edit this hook to get past it. Both are the failure this exists to prevent.

Stop and tell the user, in plain language and without jargon: which list grew, which module was added to it, what can now call what that could not before, and whether changing the CALLER was the alternative. A forbidden-reference warning usually means a caller is reaching past a seam, not that the seam is drawn too tight. Then let them decide.

Declaration: $markers$(boundary_caveats "$old" "$new")"
}

# The ratchets in .claude/rules/BUDGET may go down freely; going up is the user's call. Compare
# each `key value` line the edit produces against the one it replaces and ask when any rose.
budget_check() {
  local old="$1" new="$2" key old_value new_value raised=""
  while read -r key new_value; do
    [ -z "$key" ] && continue
    old_value="$(printf '%s\n' "$old" | awk -v key="$key" '$1 == key { print $2; exit }')"
    if [ -n "$old_value" ] && [ "$new_value" -gt "$old_value" ] 2>/dev/null; then
      raised="$raised $key $old_value→$new_value"
    fi
  done < <(printf '%s\n' "$new" | grep -E '^[a-z_]+ [0-9]+$' || true)
  [ -z "$raised" ] && exit 0

  decide ask "RATCHET: this edit raises a budget in .claude/rules/BUDGET ($raised). A budget only goes down without a decision; raising one means CLAUDE.md is allowed to grow, or a lib file may stay outside every area rule. Approve only if that is the intent — otherwise move the text into the area's .claude/rules file, or add a glob."
}

# The whole file as an Edit call would leave it: `old_string` replaced by `new_string` in the
# current contents, once or (`replace_all`) everywhere. Done in jq on the raw text — `split` and
# `join` take the strings literally, so an old_string full of regex or sed metacharacters needs no
# escaping. Prints nothing when the result cannot be known (no file, an empty or absent
# old_string); the caller then scores the fragments, which is what the tool will act on anyway.
edited_file() {
  local input="$1" path="$2"
  [ -f "$path" ] || return 0
  printf '%s' "$input" | jq -r --rawfile content "$path" '
    .tool_input as $edit
    | ($edit.old_string // "") as $from
    | ($edit.new_string // "") as $to
    | if $from == "" or ($content | contains($from) | not) then empty
      elif ($edit.replace_all // false) then $content | split($from) | join($to)
      else ($content | split($from)) as $pieces | $pieces[0] + $to + ($pieces[1:] | join($from))
      end'
}

edit_check() {
  local input tool path old new boundary_old boundary_new edited added pairs markers
  input="$(cat)"
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
  [ -n "$path" ] || exit 0

  case "$tool" in
    Edit)
      old="$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""')"
      new="$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')"
      # The boundary scorer reads a declaration from its `use Boundary` line down, so it has to see
      # the whole file: `mix format` puts a long `exports:` list on the lines BELOW `use Boundary,`,
      # and an Edit whose fragment holds only list entries otherwise scores 0 → 0 and is allowed.
      # The waiver counts below stay on the fragments — they count lines the edit adds, which is
      # what the fragments are, and `count_pairs` takes a minimum that does not subtract cleanly
      # across a whole file.
      boundary_old="$old" boundary_new="$new"
      edited="$(edited_file "$input" "$path")" || edited=""
      if [ -n "$edited" ]; then
        boundary_old="$(cat "$path")" boundary_new="$edited"
      fi
      ;;
    Write)
      new="$(printf '%s' "$input" | jq -r '.tool_input.content // ""')"
      if [ -f "$path" ]; then old="$(cat "$path")"; else old=""; fi
      boundary_old="$old" boundary_new="$new"
      ;;
    *) exit 0 ;;
  esac

  case "$path" in
    *.claude/rules/BUDGET | .claude/rules/BUDGET) budget_check "$old" "$new" ;;
  esac

  code_file "$path" || exit 0

  # Before the waiver check, because a `use Boundary` line carries no waiver marker and would
  # otherwise fall straight through to the `added <= 0` early exit below.
  boundary_check "$path" "$boundary_old" "$boundary_new"

  added=$(( $(count_markers "$new") - $(count_markers "$old") ))
  [ "$added" -le 0 ] && exit 0

  markers="$(printf '%s\n' "$new" | strip_doc_lines | grep -E "$marker_re" | grep -v 'register_attribute' | sed 's/^[[:space:]]*//' | head -3 | paste -sd '|' - || true)"
  pairs=$(( $(count_pairs "$new") - $(count_pairs "$old") ))

  if [ "$pairs" -lt "$added" ]; then
    decide deny "WAIVER GATE: this edit adds $added lint/security waiver(s) to $path ($markers) without the two lines that must sit directly above each one:
  # why: <what the code needs that trips the tool, and the invariant that keeps it safe>
  # instead of: <the alternative considered> — rejected because <reason>
First ask whether the code needs the flagged construct at all (a shell-out where Path.wildcard would do, an interpolated query where a bound parameter would do). If it does, add both lines and re-run the edit; the user will then be asked to approve the waiver."
  fi

  decide ask "WAIVER GATE: this edit adds $added lint/security waiver(s) to $path ($markers). The # why: and # instead of: lines are in the diff. Approve only if the code genuinely needs the flagged construct and the rejected alternative was weaker than the waiver."
}

# Emit the added lines of a unified diff that are waivers lacking both fields within the lookback.
scan_diff() {
  local path="$1"
  awk -v path="$path" -v marker_re="$marker_re" -v why_re="$why_re" -v instead_re="$instead_re" -v lookback="$lookback" '
    /^@@/ { start = $0; sub(/^@@ -[0-9,]+ \+/, "", start); sub(/[ ,].*$/, "", start); line = start - 1; next }
    /^(diff|index|\+\+\+|---)/ { next }
    {
      prefix = substr($0, 1, 1); text = substr($0, 2)
      if (prefix == "-") next
      line++
      buf[++n] = text
      # `!in_doc` for the same reason as strip_doc_lines above: a marker quoted in a moduledoc is
      # prose about a waiver, not a waiver. A `git mv` presents the whole file as added lines, so
      # without this every move of a file that documents a waiver is denied. The toggle sits after
      # the check because the opening `@moduledoc """` line carries no marker, and it fails in the
      # safe direction — a hunk that opens mid-docstring starts with in_doc unset and still flags.
      if (prefix == "+" && !in_doc && text ~ marker_re && text !~ /register_attribute/) {
        has_why = 0; has_instead = 0
        for (i = n - lookback; i < n; i++) if (i > 0) { if (buf[i] ~ why_re) has_why = 1; if (buf[i] ~ instead_re) has_instead = 1 }
        if (!(has_why && has_instead)) printf "%s:%d: %s\n", path, line, text
      }
      if ((split(text, doc_parts, /"""/) - 1) % 2 == 1) in_doc = !in_doc
    }'
}

# Every changed path, one per line as `<path now><TAB><path at HEAD>`. The two differ only for a
# rename, which `git status` reports as `R  old -> new`: an earlier version kept only the new path,
# looked for `HEAD:<new path>`, found nothing, and scored every grant in a moved file as new.
# `--find-renames` is explicit so a `status.renames = false` config cannot turn
# that back off. Git pairs a rename only once both halves are staged, which `git mv` does and a
# plain `mv` does not — a plain `mv` still reads as a deletion and a new file.
changed_files() {
  git status --porcelain=v1 -uall --find-renames | awk '{
    path = substr($0, 4); head = path
    arrow = index(path, " -> ")
    if (arrow) { head = substr(path, 1, arrow - 1); path = substr(path, arrow + 4) }
    printf "%s\t%s\n", path, head
  }'
}

# The boundary backstop, for a declaration widened through Bash or sed rather than the Edit tool —
# which is not a corner case: batch rewrites are how most renames are made, and the
# Edit hook never sees them. Compares the committed declaration against the working tree one.
# The declarations of every changed compiled source, hashed. An approval is granted against this
# exact state, so a further widening after one invalidates it rather than riding along. The paths
# are sorted first, as commit-gate.sh sorts its marks': `git status` lists an untracked file after
# every tracked one and a staged new file in path order, so staging alone reordered the list and
# refused the commit an approval had been recorded for, with no declaration changed.
widening_state() {
  local path
  {
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      compiled_source "$path" || continue
      if [ -f "$path" ]; then
        printf '%s %s %s\n' "$path" "$(boundary_grants "$(cat "$path")")" "$(boundary_count "$(cat "$path")")"
      else
        printf '%s deleted\n' "$path"
      fi
    done < <(changed_files | cut -f1 | sort -u)
  } | sha256sum | cut -d' ' -f1
}

# The user's decision, recorded. Same standing as commit-gate.sh's `mark` commands and the same
# honesty note: nothing physically stops this being run without asking, so the ONLY documented path
# is immediately after the user says proceed, on a widening they have seen in plain language. The
# deny is what forces that conversation; this is what lets the answer be acted on.
approve_widening() {
  local marks_dir
  marks_dir="$(git rev-parse --git-dir)/claude-skill-marks"
  mkdir -p "$marks_dir"
  widening_state >"$marks_dir/boundary-approval"
  echo "recorded the user's approval for the current boundary declarations"
}

widening_approved() {
  local marks_dir approved
  marks_dir="$(git rev-parse --git-dir)/claude-skill-marks"
  [ -f "$marks_dir/boundary-approval" ] || return 1
  approved="$(cat "$marks_dir/boundary-approval")"
  [ "$approved" = "$(widening_state)" ]
}

scan_boundary() {
  local path="$1" head_path="$2" old new before after
  compiled_source "$path" || return 0
  if git cat-file -e "HEAD:$head_path" 2>/dev/null; then old="$(git show "HEAD:$head_path")"; else old=""; fi
  new="$(cat "$path")"
  case "$new$old" in *"use Boundary"*) ;; *) return 0 ;; esac

  if [ "$(boundary_classifications "$old")" != "$(boundary_classifications "$new")" ] && ! widening_approved; then
    printf '%s: a classify_to: target changed, moving a module between boundaries — raise it with the user (which module, out of where, into where, and what it can now call), then record their answer with: bash .claude/hooks/waiver-gate.sh approve-widening\n' "$path"
    return 1
  fi

  if [ "$(boundary_count "$new")" -lt "$(boundary_count "$old")" ] && ! widening_approved; then
    printf '%s: a use Boundary declaration was removed, folding its modules into the parent boundary, where every module may call them — raise it with the user in plain language (which boundary goes, which modules lose it, what can now call them), then record their answer with: bash .claude/hooks/waiver-gate.sh approve-widening\n' "$path"
    return 1
  fi

  before="$(boundary_grants "$old")"
  after="$(boundary_grants "$new")"
  [ "$after" -le "$before" ] && return 0

  # The user's recorded decision, hashed against these exact declarations — so an approval covers
  # the widening they were shown and nothing that arrives after it.
  widening_approved && return 0

  printf '%s: boundary grant widened (permission score %s → %s) — raise it with the user in plain language (which list grew, which module joined it, what can now call what), then record their answer with: bash .claude/hooks/waiver-gate.sh approve-widening%s\n' \
    "$path" "$before" "$after" "$(boundary_caveats "$old" "$new")"
  return 1
}

# A declaring file deleted outright — through Bash, `git rm`, or a plain `mv` that git has not
# paired as a rename. When nothing remains under its namespace the boundary went with its code,
# which widens nothing; when modules remain, they fold into the parent exactly as if the
# declaration had been deleted from the file. The namespace is read from the path, the convention
# every boundary here follows.
scan_deleted_boundary() {
  local head_path="$1" namespace
  compiled_source "$head_path" || return 0
  git cat-file -e "HEAD:$head_path" 2>/dev/null || return 0
  [ "$(boundary_count "$(git show "HEAD:$head_path")")" -gt 0 ] || return 0
  namespace="${head_path%.ex}"
  [ -n "$(find "$namespace" -name '*.ex' 2>/dev/null | head -1)" ] || return 0
  widening_approved && return 0

  printf '%s: deleted, but its use Boundary declaration covered modules that remain under %s/, which fold into the parent boundary, where every module may call them — raise it with the user in plain language (which boundary goes, which modules lose it, what can now call them; if the file moved, `git mv` it so the move is paired), then record their answer with: bash .claude/hooks/waiver-gate.sh approve-widening\n' \
    "$head_path" "$namespace"
  return 1
}

diff_check() {
  local path head_path moved_from status=0 output
  while IFS=$'\t' read -r path head_path; do
    [ -z "$path" ] && continue
    code_file "$path" || continue
    if [ ! -f "$path" ]; then
      scan_deleted_boundary "$head_path" || status=1
      continue
    fi
    if [ "$head_path" != "$path" ] && git cat-file -e "HEAD:$head_path" 2>/dev/null; then
      # A moved file is diffed against the file it was at HEAD, so it shows only what changed in
      # the move; against itself every line is added, and any waiver written before the fields
      # were required fails the move. Not `git diff HEAD --find-renames`: that re-guesses the
      # pairing from the working tree, and a small file edited in the move falls under git's 50%
      # similarity line and splits back into a deletion and a new file. `git status` already
      # paired them against the index, so the pairing is taken from there.
      moved_from="$(mktemp)"
      git show "HEAD:$head_path" >"$moved_from"
      output="$(git diff --no-index -U"$lookback" "$moved_from" "$path" | scan_diff "$path" || true)"
      rm -f "$moved_from"
    elif git cat-file -e "HEAD:$path" 2>/dev/null; then
      output="$(git diff HEAD -U"$lookback" -- "$path" | scan_diff "$path")"
    else
      output="$(git diff --no-index -U"$lookback" /dev/null "$path" 2>/dev/null | scan_diff "$path" || true)"
    fi
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
      status=1
    fi
    scan_boundary "$path" "$head_path" || status=1
  done < <(changed_files)
  exit "$status"
}

case "${1:-}" in
  edit) edit_check ;;
  diff) diff_check ;;
  approve-widening) approve_widening ;;
  *) echo "usage: waiver-gate.sh edit|diff|approve-widening" >&2; exit 1 ;;
esac
