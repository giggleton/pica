# Module boundaries

**Applies to:** `lib/pica/**/*.ex`.

## The rule

A namespace's root module is its public API; the modules beneath it are implementation. Other
namespaces are consumers of that API and don't reach past it.

`use Boundary` makes the large version of this a compiler check: a call across a declared
boundary that its `deps:` and `exports:` do not permit fails the build (CLAUDE.md, Approach &
architecture). This review covers the two things the compiler cannot judge — whether a *grant*
was the right answer when a call was forbidden, and the same discipline **inside** one boundary,
where Boundary sees nothing at all.

## Findings

### 1. A boundary widened instead of a caller fixed — High

A diff that adds to a `deps:` or `exports:` list, lifts a module with `top_level?:`, or adds a
`dirty_xrefs:` entry, in order to silence a forbidden-reference warning.

```elixir
# in MyLib — finding
use Boundary, exports: [Parser, Parser.Tokens, Formatter]   # Parser.Tokens was just added
```

A forbidden-reference warning usually means a caller is reaching past a seam, not that the seam
is drawn too tight. `.claude/hooks/waiver-gate.sh` already denies the edit until it has been
explained to the user; the review's job is to check that the explanation held: what can now call
what that could not before, and what the alternative in the *caller* was. If a function on the
root module would have served the caller, that is the finding, and the export is its symptom.

### 2. Reaching into another namespace's internals — Medium

Calling a module beneath another namespace's root — `MyLib.Parser.Tokens.split/1` from
`MyLib.Formatter` — when `MyLib.Parser` is the API.

```elixir
# in MyLib.Formatter — finding
tokens = MyLib.Parser.Tokens.split(source)
```

Inside one boundary the compiler allows it; the review does not. The knowledge of how `Parser`
is put together now lives in `Formatter`, and it is wrong the day `Parser` changes its shape.
Correct shape: `MyLib.Parser.tokenize(source)`, and a deliberate decision if `Tokens` is meant to
be public — then it is exported, and said so.

### 3. Circular dependencies between namespaces — Medium

`Parser` calls `Formatter` and `Formatter` calls `Parser`. Legal in Elixir, but it means the two
aren't really separate. Report once with both directions named; don't file it repeatedly for
each call site. The fix is usually extracting the shared concept, or passing data in rather than
calling back.

### 4. Logic in a data module — Medium

A module whose job is to describe a shape — a struct, an options record, a spec — that
orchestrates, performs IO, or calls into other namespaces.

```elixir
# in MyLib.Document — finding
def save(document) do
  document |> MyLib.Store.write!() |> MyLib.Index.refresh()
end
```

Constructors, guards, `defstruct`, types, and pure folds over the module's own fields are all
correct here and not findings. The line is IO and calls out.

### 5. A core module that is no longer pure — High

In Pica the library is a pure core of functions over fonts and strings, apart from the modules
`.credo.exs` excludes from `CorePurity` by name, each with its reason. Every boundary is strict
(the `mix.exs` default), so Boundary forbids any library or domain a boundary's `deps:` does not
name, and the `CorePurity` credo check, run over the rest of `lib/`, fails the gate on the
standard-library escapes Boundary cannot see: a clock read, a config read, unseeded randomness, a process or IO call. What is
left to the review is the borderline — a value computed from "now" or from config two calls
upstream, a function that would be pure if its one impure input were an argument. The fix is the
same every time: take the value as an argument, and let the shell above the core read it.

## Not a finding

- **One namespace calling another's root module API.** `MyLib.Parser.tokenize/1` from inside
  `Formatter` is correct and expected. This is the most likely false positive in the file and the
  one that would make the check unusable: cross-namespace *calls* are the design, cross-namespace
  *internals* are the violation.
- **Passing another namespace's structs around.** Receiving a `%Parser.Token{}` and reading its
  fields is a value being used, not a boundary being crossed.
- **Shared infrastructure** — a `Settings` module, a `Clock`, telemetry helpers. Not namespaces
  with an API to protect.
- **Test files.** Setup blocks legitimately reach across namespaces. Don't review `test/` under
  this rule.
- **A documented exception.** A comment explaining why the boundary is crossed, or an `exports:`
  entry the user approved in conversation, is a decision already made; note it in one line at
  most, or say nothing.

## Judgment calls

The question that resolves most cases: **would this module still compile and pass its tests if
the other namespace changed how it is implemented?** The answer should be yes for every module
but the owner.

Two namespaces that always change together, are always called together, and can't be reasoned
about independently may not be two namespaces. If one pair generates most of the findings, that
is the report-level observation worth making, and it is more useful than the individual
violations. Say it once at the top rather than filing the same structural problem six times.

## Overlap with other checks

Logic in a GenServer callback that also reaches into another namespace trips both this rule and
`otp-processes.md`. Report it **once**, under the OTP check — relocating the logic resolves both.
