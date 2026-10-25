# pica — Design Notes

The design overview, the decision log and an index of milestones. CLAUDE.md says what applies to
every session; the area files under `.claude/rules/` give each area's invariants and the modules'
documentation how it works; this file says **why** — what was decided and what was rejected — and
indexes what shipped when, each commit's message telling its story. It is reference: read an
entry by name, never the whole file. The `docs-sync` skill routes changes here;
`.claude/rules/docs.md` is the shape.

## 1. What we're building

Pica measures text from font files, through HarfBuzz's shaping. A caller registers font files
under a family name, then asks, by family and face, for each string's glyphs: which glyph, which
characters it came from, how far it advances with kerning, ligatures and contextual forms applied,
and how far it would advance unshaped. It also reports font-wide metrics and glyph bounding boxes,
in font units or at a scale the caller gives, with HarfBuzz's rounding. Nothing is drawn.

Its first consumer is Giggly (`~/repos/giggly`), whose layout is sized by measured text and must
match R's svglite 2.2.2, which measures through HarfBuzz. Later, any Elixir code that lays out
text: PDF writers, image generators, charts. Pica is one of the Giggleton family of packages
anchored by Giggly, but never depends on it.

The plan, with the survey and the measurements it rests on (R's widths for Lato, the test fonts'
tables, the crates read), is working material outside the repo, in
`~/.claude/plans/pica/text-shaping-package.md`, as CLAUDE.md asks of plans. What is drawn from it
moves into §4, with its rejected alternatives, as each decision is ratified.

## 2. Architecture & principles

- **A Rust NIF does all the reading and shaping**; the Elixir side validates options, names
  errors and holds the registry. The crate lives in `native/pica` and ships prebuilt through
  `rustler_precompiled`.
- **Expected values come from outside tools** — fontTools, `hb-shape`, R — never from Pica's own
  output (§5).
- **Pica returns the font's numbers and HarfBuzz's positions**; a caller's own rules (R's grids,
  R's line heights) stay with the caller.

## 3. Module map

`Pica` is the public API and the root boundary; `Pica.Native` holds the NIF stubs. `mix
boundary.spec` prints the current graph.

## 4. Key design decisions (the "why", so we don't relitigate)

**A separate package, not a part of Giggly** (Steve, 2026-10-24). Pica is its own Mix project and
repository, added to Giggly as an optional dependency: with Pica installed, Giggly asks it for a
family; without it, or for a family Pica does not have, Giggly falls back to its built-in
Liberation Sans table. Text measurement is useful well beyond plotting. Rejected: a module inside
Giggly — it would make every Giggly user compile or download a NIF, and keep the measuring from
anyone else.

**HarfBuzz's Rust port through a Rustler NIF, shipped with `rustler_precompiled`** (Steve,
2026-10-24). Prebuilt binaries per platform are downloaded at compile time and checked against a
checksum file; a source build is the fallback. Rejected, from a survey of Hex on 2026-10-24:
`truetype_metrics`/`font_metrics` (legacy `kern` table only, and Google fonts kern only in GPOS);
`opentype` (dead, a class-kerning bug); `tincture` (follows no GPOS extension lookups, so reads none
of Lato's kerning); `harfbuzz_ex` (a GenServer per font, no metrics, reads paths itself); measuring
by rendering with `resvg` or `vix` (an ink box is not an advance: "A" is 8.052 inked, 8.125
advanced). Even a correct GPOS reader would not do ligatures or contextual forms, which R applies.

**The crates: harfrust, read-fonts and skrifa, wuff** (2026-10-24). harfrust is HarfBuzz's own
Rust port, matching HarfBuzz 15.0.0, built on Google Fonts' read-fonts; skrifa gives metrics and
outlines; wuff decodes WOFF and WOFF2. Rejected: `rustybuzz`/`ttf-parser` (no release since
2024-11; harfrust is the successor); `harfbuzz_rs`/`harfbuzz-sys` (C HarfBuzz itself, but a C++
build for every platform); `allsorts` (a smaller community); `swash`, `fontdue` (reads `kern` but
never applies it); `cosmic-text`, `parley` (whole layout engines).

**No font parser written in Elixir** (Steve, 2026-10-24). Everything read from a font is read in
Rust. Rejected: parsing tables in Elixir and shaping in Rust — two readers of one font, which can
disagree.

**Family names are the input** (Steve, 2026-10-24). A caller asks by family name and face, and
never passes font values through its own data (Giggly's plot description). How a name finds its
files is the next entry.

**A name finds the fonts the app gave Pica first, then the machine's installed fonts, unless the
app opts out** (Steve, 2026-10-24; the plan's decision A). Fonts handed to Pica always win, so an
app or a test can pin an exact file; the installed fonts are a fallback that is on by default,
because a machine that happens to have a font should simply get it. Names match exactly, with no
aliasing (`"sans"` never becomes DejaVu), and a name found in neither place is `:error`, so Pica
still never substitutes. The machine's fonts are scanned lazily, at the first name the given fonts
lack, and remembered. How an app opts out is the entry beginning "An app opts out". Rejected: given fonts only
(machine-independent, but a font the machine has goes unused, and tests pin their fonts anyway);
installed fonts only by opt-in (the same, unless every app remembers to ask); no lookup by name,
only handles the caller keeps (names are the input, the entry above).

**A face the app did not give falls through to the installed fonts** (Steve, 2026-10-24). When an
app gave Lato's regular face but not its bold, a request for Lato bold looks for an installed Lato
bold, as svglite does for a user font's missing face; found nowhere, or with the installed fonts
opted out, it is `:error`. A handle is therefore always the face that was asked for. Rejected: the
given regular face standing in (systemfonts' `register_font()` default, which the plan proposed,
with `Pica.face/1` to say which face a handle really is), since it substitutes silently; `:error`
straight away, since it ignores a bold the machine has.

**The fonts given to Pica live in `:persistent_term`, one key per family** (Steve, 2026-10-24;
the plan's decision D). Given once at startup, a family is found by name from anywhere afterwards:
a read costs nothing and copies nothing, while a write triggers a global garbage collection, which
suits fonts given at startup and not per request. The installed fonts Pica remembers after a scan
are shared state too, and sit beside them. The registry is the one impure module, excluded from
`CorePurity` by name. Rejected: an ETS table owned by a Pica process (cheaper writes, but a
process to start and supervise, for writes that happen once); a registry value the caller holds
(pure, but it must travel to every place that measures text).

**An app opts out of installed fonts per lookup, with `installed: false`** (Steve, 2026-10-24).
The option defaults to `true`, and nothing global records the choice, so one caller's opt-out
never changes another's results; a consumer such as Giggly passes it through for the app that
uses it. Rejected: a switch set once at startup in shared memory (covers every lookup without the
consumer knowing, but it is global state one caller flips for all); application config (the Elixir
convention, but a config read inside Pica, which `CorePurity` forbids).

**Numbers come back in font units, or at a `scale:` with HarfBuzz's rounding** (Steve,
2026-10-24; the plan's decision E). Without the option Pica returns the font's own integers, which
depend on no size. With `scale:` an integer, harfrust's `ShaperFont::set_scale` positions every
glyph at that scale, rounded per glyph as HarfBuzz rounds; `scale: 12 * 64` gives 1/64 point at
12 points, svglite's grid. Rejected: points at a size the caller gives (friendlier, but fractions
with the per-glyph rounding lost, so svglite's widths cannot be matched); font units only (the
same flaw, since rounding inside shaping cannot be redone from outside).

**Shaping uses HarfBuzz's defaults** (Steve, 2026-10-24; the plan's decision F). The features
HarfBuzz turns on for the text's script (`kern`, `liga`, `clig`, `calt`, `mark`, `mkmk`, `ccmp`,
`locl` and the rest) are on, and the direction and script are guessed from the text; `features:`,
`direction:`, `script:` and `language:` override them per call. That is what svglite and browsers
do, so Pica's widths match what R measures and what a browser draws. Rejected: defaults of Pica's
own choosing (kerning only, say), which would differ from both for no gain.

**Giggly holds the adapter; Pica defines no behaviour for it** (Steve, 2026-10-24). Pica exposes
a general API with no knowledge of Giggly, and Giggly compiles its adapter behind
`Code.ensure_loaded?(Pica)`. Rejected for now: a behaviour in Giggly that Pica implements — it
would tie Pica's release to Giggly's.

**Giggly keeps R's rules** (Steve, 2026-10-24). Rounding to R's grids, the ascent of "M", the
descent of "gjpqyQ", what a missing character measures: Giggly applies them to the numbers Pica
returns. Rejected: an R mode in Pica — R-specific behaviour in a general package.

**The name is Pica; the licence is MIT** (Steve, 2026-10-24). A pica is a printer's measure, and
the creature can live in Giggleton.

**The harness is Giggly's, copied, without mutation testing** (Steve, 2026-10-24). Pica takes
Giggly's copies of Tack's files, which carry fixes Tack's templates do not yet have
(`.claude/rules/dependencies.md`, "How it works"), and drops Giggly's `muex`, its skill and the
commit gate's mutation rule. Rejected: `mix tack.install` — it would install the older templates.

**Tack's code is copied into `dev/`, not depended on** (Steve, 2026-10-24). Tack's repository is
private, so CI could not fetch the `tack` dependency. The gate runner, the rules check, the
boundary scanner, the credo checks and their tests are copied byte for byte from Tack's commit
9ae74d8, compiled in dev and test only, and left out of the package; the copied mix tasks and the
`Tack` boundary were approved one at a time. Rejected: making Tack public (no change to Pica, but
Tack stays private); dropping Tack and its checks (the gate would lose the rules it enforces); a
CI deploy key for Tack (CI would pass, but a contributor still could not run the gate).

## 5. Testing approach

Expected values come from outside tools, never from Pica's own output: fontTools in
`python:3.12-slim`, `hb-shape` from Debian's `libharfbuzz-bin`, and R for svglite's widths. Each
generator script lives under `test/support/ground_truth/` with its Docker command in its header,
and its output under `test/fixtures/` as Elixir terms. Test fonts are full original files under
`test/fonts/`, each with its licence and a `FONTS.md` entry naming its source, version and
SHA-256 — no subsets, since Lato and Lobster reserve their names under the OFL.

## 6. Milestone log

One line per milestone, newest first: the date, the commit's subject as its title (so
`git log --grep` finds it), and the §4 entries it settled. The commit message tells the story.

- 2026-10-24 — Copy Tack's gate tooling into dev/ so CI needs no private repository; §4: "Tack's
  code is copied into `dev/`"
- 2026-10-24 — Start Pica: a NIF skeleton built from source, Giggly's harness, and the plan's
  decisions settled; §4: every entry

## 7. Deferred / open questions

Open: CI on macOS (`erlef/setup-beam` runs on Linux and Windows only); whether 0.1.0 reads
font collections; variable fonts beyond the default instance (recommended after 0.1.0).
