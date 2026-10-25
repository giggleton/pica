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

`Pica` is the public API and the root boundary; `Pica.Font` is the opaque struct a loaded font comes
back in; `Pica.Glyph` is a shaped glyph; `Pica.ShapeOptions` checks shaping's options;
`Pica.Native` holds the NIF stubs. `mix boundary.spec` prints the current graph.

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

**0.1.0 reads font collections** (Steve, 2026-10-24). `load(bytes, index: n)` picks a font from
a `.ttc` or `.otc` file, and an index past the end is `{:index_out_of_range, font_count}`. Since
installed fonts are a fallback in 0.1.0, collections matter: macOS ships Helvetica and Avenir as
collections, Noto its CJK fonts. read-fonts reads them natively, and the test collection is built
from Roboto, whose licence reserves no name. Rejected: leaving collections out of 0.1.0, which
would make the fallback find installed fonts it could not open.

**`info/1` keeps a font's container and its outlines apart** (2026-10-24). Where the plan had one
`format`, `info/1` reports `container` (`:sfnt`, `:collection`, `:woff`, `:woff2`: what the bytes
were) and `outlines` (`:truetype`, `:cff`, `:cff2`, `:none`: what draws the glyphs), since a WOFF2
can wrap either outline format; and `axes` in place of a `variable` flag, which they imply. Load
errors are an atom or a tagged tuple naming the problem: `:unknown_format`, `:truncated`,
`{:index_out_of_range, font_count}`, `{:missing_table, tag}`, `{:malformed, detail}`. Rejected: a
single `format`, which cannot say both.

**Glyphs are measured by glyph id** (Steve, 2026-10-25). `nominal_advances/2` and
`glyph_boxes/2` take lists of glyph ids, as shaping returns them, so a caller measures the glyphs
shaping produced, ligatures and alternates included; `glyph_ids/2` maps text through the
character map alone, one id per code point, 0 for a character the font lacks, which is how
FreeType picks the glyph R measures for "M". Rejected: taking a string, as the plan sketched
(reaches only glyphs a character maps to, and cannot measure shaped output); one function
taking either (a list of integers is also a charlist).

**A glyph's box is its outline's control box** (Steve, 2026-10-25). Every glyph, in every outline
format, is drawn through skrifa into a control-box pen: the box of every point, on and off the
curve, which FreeType 2.14.3 computes (`ttgload.c`, `compute_glyph_metrics`) and R measures. The
box a `glyf` glyph stores is ignored; in the test fonts five disagree with their points. skrifa,
like FreeType unscaled, rounds each point of a scaled composite component to a whole unit, and
Pica keeps that; a CFF corner between units is rounded outward. Rejected: the stored `glyf` box
(fast, but not what FreeType reports); exact composite points rounded outward (needs a second
outline reader beside skrifa, and is still integers).

**A glyph with no outline has no box: `:none`** (Steve, 2026-10-25). A space has no points, and
fontTools agrees. A caller copying R, where FreeType reports zeros, maps `:none` to zeros itself.
Rejected: `{0, 0, 0, 0}` — it claims ink at the origin, so the leftmost ink of " A" would be 0.

**A glyph id the font lacks raises `ArgumentError`** (Steve, 2026-10-25). Ids come from the same
font, so one past `glyph_count` means fonts were mixed up: a programmer error, raised by the
public API as misuse is. Rejected: `:none` in its place (holes in a plausible list, and `:none`
meaning two things in `glyph_boxes/2`); `{:error, reason}` for the call (every measurement
unwrapped for a case only a bug produces).

**`shape/3` shapes one string** (Steve, 2026-10-25). `shape(font, text, options)` returns one
string's glyphs, as `glyph_ids/2` takes one string, with one result type, and options such as a
feature apply to that string alone. harfrust keeps a font's prepared layout tables on the font,
so a call does little beyond the shaping itself: measured, 10 to 15 µs a label. Rejected: a list
of strings, as the plan sketched (one trip into Rust per batch, saving about a microsecond a
string, with every option applying to every string); either, by type (two return shapes behind
one name). A batch function can be added beside it if step 9's benchmarks call for one.

**Each shaped glyph is a `%Pica.Glyph{}`** (Steve, 2026-10-25). Its fields, `glyph_id`,
`cluster`, `x_advance`, `nominal_advance`, `x_offset` and `y_offset`, are named, so two advances
cannot be swapped by position, a misspelt field fails to compile, and a field can be added (a
`y_advance` for vertical text) without breaking a caller. Rust builds the struct. It costs a map
per glyph, an estimated 0.1 to 0.2 µs, small for one label's glyphs; the NIF rule that measures
cross as tuples was written when `shape` was to take a list of strings. Rejected: a six-tuple
(cheapest, and as `glyph_boxes/2` returns, but positional); a plain map (named, with no type).

**Clusters count characters** (Steve, 2026-10-25). A glyph's cluster is the index, from 0, of the
first code point of the characters it came from, as `glyph_ids/2` counts and as hb-shape reports
by default; harfrust's buffer is filled a code point at a time to give it. Rejected: UTF-8 byte
offsets (harfrust's own unit, and what `binary_part/3` takes, but no other Pica function counts
bytes).

**Shaping's options take HarfBuzz's forms** (Steve, 2026-10-25). `features:` is a keyword list
of four-character tags and `true`, `false` or a number, for the whole text; `direction:` is
`:left_to_right` or `:right_to_left`; `script:` a four-letter ISO 15924 code in any case;
`language:` a BCP 47 tag. Left out, direction and script are guessed from the text and the
language is none, never the machine's locale. A value not of its form raises; one of the right
form passes whether or not the font or Unicode knows it, as in HarfBuzz. Rejected: HarfBuzz's
feature strings (`"-kern"`, ranges, but checked only as strings); feature ranges now (addable
later as a `{value, range}` value); vertical directions (they need `y_advance`, and a rotated
label is horizontal text); a strict list of scripts (Pica would keep ISO 15924 current); script
names as atoms; English as the default language.

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
`python:3.12-slim`, `hb-shape` from Debian's `libharfbuzz-bin` (installed in that image, so a
generator can decode a WOFF with fontTools before shaping it), and R for svglite's widths. Each
generator script lives under `test/support/ground_truth/` with its Docker command in its header,
and its output under `test/fixtures/` as Elixir terms. Test fonts are full original files under
`test/fonts/`, each with its licence and a `FONTS.md` entry naming its source, version and
SHA-256 — no subsets, since Lato and Lobster reserve their names under the OFL.

## 6. Milestone log

One line per milestone, newest first: the date, the commit's subject as its title (so
`git log --grep` finds it), and the §4 entries it settled. The commit message tells the story.

- 2026-10-25 — Shape characters a font lacks to glyph 0, and hide invisible ones as HarfBuzz
  does; §4: "Shaping uses HarfBuzz's defaults"
- 2026-10-25 — Shape text through harfrust, with HarfBuzz's defaults and per-call options; §4:
  "`shape/3` shapes one string", "Each shaped glyph is a `%Pica.Glyph{}`", "Clusters count
  characters", "Shaping's options take HarfBuzz's forms"
- 2026-10-25 — Measure each glyph's advance and box, and map characters to glyphs; §4: "Glyphs
  are measured by glyph id", "A glyph's box is its outline's control box", "A glyph with no
  outline has no box", "A glyph id the font lacks raises"
- 2026-10-24 — Load fonts from every container and report what each says about itself; §4: "0.1.0
  reads font collections", "`info/1` keeps a font's container and its outlines apart"
- 2026-10-24 — Copy Tack's gate tooling into dev/ so CI needs no private repository; §4: "Tack's
  code is copied into `dev/`"
- 2026-10-24 — Start Pica: a NIF skeleton built from source, Giggly's harness, and the plan's
  decisions settled; §4: every entry

## 7. Deferred / open questions

Open: CI on macOS (`erlef/setup-beam` runs on Linux and Windows only); variable fonts beyond the
default instance (recommended after 0.1.0); a batch shaping function, if step 9's benchmarks
call for one.
