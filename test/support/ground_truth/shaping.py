# Writes test/fixtures/shaping.exs: what hb-shape, HarfBuzz's own command-line shaper, makes of
# each test string in each test font, which is what `Pica.shape/3` must return.
#
# Run from the repository root:
#
#   docker run --rm -v "$PWD":/work -w /work -e OWNER="$(id -u):$(id -g)" python:3.12-slim sh -c \
#     'apt-get update -qq && apt-get install -y -qq libharfbuzz-bin > /dev/null \
#      && pip install --quiet fonttools==4.67.0 brotli==1.2.0 uharfbuzz==0.57.0 \
#      && python -I test/support/ground_truth/shaping.py \
#      && chown "$OWNER" test/fixtures/shaping.exs'
#
# python:3.12-slim is Debian, so libharfbuzz-bin is Debian's build of hb-shape; the fixture's
# header records its version. Rerun it when a test font or a test string changes.
#
# hb-shape runs with its defaults but for the options a case sets: the font's units per em as its
# scale, so every number is in font units, unless the case sets a scale (`--font-size`, with no
# subpixel bits, is the scale); HarfBuzz's own font functions (`ot`); clusters counted
# in characters (Unicode code points), not bytes; and direction and script guessed from the text.
# It runs with no locale in its environment, since it takes its default language from $LANG and
# Pica's default is no language. hb-shape reads no WOFF or WOFF2, so those are decoded by fontTools
# first, to the plain font they wrap.
#
# For each glyph: its glyph id, cluster, x_advance, x_offset and y_offset from hb-shape, and its
# nominal advance: the glyph's advance width in hmtx, read by fontTools, or, at a scale, that
# advance as HarfBuzz scales it, asked of HarfBuzz itself through uharfbuzz (which bundles its own
# HarfBuzz; the fixture's header records the version), since hb-shape does not report it.

import json
import os
import platform
import subprocess
import tempfile

import fontTools
import uharfbuzz
from fontTools.ttLib import TTFont

FONTS = "test/fonts"
TARGET = "test/fixtures/shaping.exs"

SIGNATURES = (b"\x00\x01\x00\x00", b"true", b"OTTO", b"ttcf", b"wOFF", b"wOF2")

# The strings R's widths were measured on (the plan's section 4.2).
R_WIDTHS = [
    "A", "V", "AV", "T", "o", "To", "f", "i", "fi", "office", "W", "a", "Wa", "AVATAR To", "M",
    "gjpqyQ",
]
R_SHAPED = [
    "Fuel efficiency (mpg)",
    "Weight (1000 lbs)",
    "Average Temperature, °F",
    "Highway miles per gallon",
    "Office affiliation",
    "1971",
]
DIGITS = ["0123456789", "1,234.56"]
PUNCTUATION = [".,:;!?'\"()[]{}-/\\@#%&*+=<>", "“Curly” ‘quotes’ … – — «guillemets»"]
LIGATURES = ["ffi", "ffl", "affluent fjord"]
# Precomposed é and ü, then the same letters as a base and a combining mark (U+0301 acute,
# U+0308 diaeresis), and two marks stacked on one base (U+0323 dot below, U+0302 circumflex).
ACCENTS = ["é", "ü", "é", "ü", "café naïve über", "ậ"]
# An Arabic label ("hello") and a Hebrew one ("peace"), unpointed and pointed: right to left.
RIGHT_TO_LEFT = ["مرحبا", "שלום", "שָׁלוֹם"]
# Characters a font may lack: the black star (U+2605), alone and between letters, and the
# mathematical bold capital A (U+1D400), past the Basic Multilingual Plane, so one character of
# four UTF-8 bytes. Then characters Unicode marks as default-ignorable, which HarfBuzz hides
# rather than drawing as missing: a soft hyphen (U+00AD), a zero-width joiner (U+200D) and a
# zero-width space (U+200B).
MISSING = ["★", "A★V", "x\U0001d400y", "co\u00adop", "a\u200db", "a\u200bb"]

NO_LIGATURES = [("liga", False), ("clig", False), ("calt", False)]
NO_KERNING = [("kern", False)]


class Atom(str):
    pass


class Keyword(list):
    pass


def options(features=(), **settings):
    pairs = []
    if features:
        pairs.append(("features", Keyword(features)))
    for name in ("direction", "script", "language", "scale"):
        if name in settings:
            pairs.append((name, settings[name]))
    return Keyword(pairs)


# 12 points in 1/64 point, as svglite measures, and a scale that is not a multiple of 64.
SCALES = [768, 1000]

CASES = (
    [(text, options()) for text in R_WIDTHS + R_SHAPED + DIGITS + PUNCTUATION + LIGATURES]
    + [(text, options()) for text in ACCENTS + RIGHT_TO_LEFT + MISSING]
    + [
        (text, options(features=features))
        for text in R_SHAPED
        for features in (NO_LIGATURES, NO_KERNING, NO_LIGATURES + NO_KERNING)
    ]
    + [
        ("0123456789", options(features=[("onum", True)])),
        ("Small Caps", options(features=[("smcp", True)])),
        ("Rag office", options(features=[("salt", 2), ("ss01", True)])),
        ("AV", options(direction=Atom("right_to_left"))),
        ("שלום", options(direction=Atom("left_to_right"))),
        ("AV", options(script="Hebr")),
        ("AV", options(script="hebr")),
        ("AV", options(script="Abcd")),
        ("שָׁלוֹם", options(script="Latn")),
        ("fi", options(language="tr")),
        ("office", options(language="TR")),
        ("şţ", options(language="ro")),
        ("ijs IJs", options(language="nl")),
        ("fi", options(language="en_US")),
        (
            "AVATAR To",
            options(
                features=NO_KERNING,
                direction=Atom("right_to_left"),
                script="Latn",
                language="tr",
            ),
        ),
    ]
    + [
        (text, options(scale=scale))
        for scale in SCALES
        for text in R_WIDTHS + R_SHAPED + ACCENTS + RIGHT_TO_LEFT
    ]
    + [
        (text, options(features=features, scale=768))
        for text in R_SHAPED
        for features in (NO_LIGATURES, NO_KERNING, NO_LIGATURES + NO_KERNING)
    ]
)

# No locale, so hb-shape's default language is none.
ENVIRONMENT = {
    name: value
    for name, value in os.environ.items()
    if name != "LANG" and not name.startswith("LC_")
}


def font_count(path):
    with open(path, "rb") as file:
        header = file.read(12)
    if header[0:4] not in SIGNATURES:
        return 0  # a licence or FONTS.md
    if header[0:4] != b"ttcf":
        return 1
    return int.from_bytes(header[8:12], "big")


def plain_font(path, scratch):
    with open(path, "rb") as file:
        signature = file.read(4)
    if signature not in (b"wOFF", b"wOF2"):
        return path
    font = TTFont(path)
    font.flavor = None
    plain = os.path.join(scratch, os.path.basename(path) + ".sfnt")
    font.save(plain)
    return plain


def feature_setting(tag, value):
    return tag + "=" + str(int(value))


# The text goes in a file, which hb-shape reads as UTF-8: with no locale, it refuses an argument
# that is not ASCII.
def hb_shape(path, index, text, settings, scratch):
    text_file = os.path.join(scratch, "text.txt")
    with open(text_file, "w", encoding="utf-8") as file:
        file.write(text)
    command = [
        "hb-shape",
        "--font-funcs=ot",
        "--no-glyph-names",
        "--output-format=json",
        "--face-index=" + str(index),
        "--font-file=" + path,
        "--text-file=" + text_file,
    ]
    for name, value in settings:
        if name == "features":
            command.append("--features=" + ",".join(feature_setting(*pair) for pair in value))
        elif name == "direction":
            command.append("--direction=" + {"left_to_right": "ltr", "right_to_left": "rtl"}[value])
        elif name == "scale":
            command.append("--font-size=" + str(value))
        else:
            command.append("--" + name + "=" + value)
    result = subprocess.run(command, capture_output=True, text=True, check=True, env=ENVIRONMENT)
    return json.loads(result.stdout)


# A glyph's advance width in hmtx, or, at a scale, as HarfBuzz scales it.
def nominal_advance(font, harfbuzz_face, glyph_id, settings):
    scale = dict(settings).get("scale")
    if scale is None:
        return font["hmtx"][font.getGlyphOrder()[glyph_id]][0]
    harfbuzz_font = uharfbuzz.Font(harfbuzz_face)
    harfbuzz_font.scale = (scale, scale)
    return harfbuzz_font.get_glyph_h_advance(glyph_id)


def shaped(path, file, index, scratch):
    plain = plain_font(path, scratch)
    font = TTFont(plain, fontNumber=index)
    with open(plain, "rb") as bytes_file:
        harfbuzz_face = uharfbuzz.Face(uharfbuzz.Blob(bytes_file.read()), index)
    entries = []
    for text, settings in CASES:
        glyphs = [
            (glyph["g"], glyph["cl"], glyph["ax"],
             nominal_advance(font, harfbuzz_face, glyph["g"], settings), glyph["dx"], glyph["dy"])
            for glyph in hb_shape(plain, index, text, settings, scratch)
        ]
        entries.append(
            {"file": file, "index": index, "text": text, "options": settings, "glyphs": glyphs}
        )
    return entries


# Elixir terms laid out as `mix format` lays them out, so the formatter leaves the file alone: a
# collection that does not fit on its line puts each element on a line of its own.
def elixir(value, indent="", prefix=0):
    inner = indent + "  "
    if isinstance(value, Atom):
        return ":" + value
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return repr(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("#{", "\\#{")
        return '"' + escaped + '"'
    if isinstance(value, tuple):
        return "{" + ", ".join(elixir(item) for item in value) + "}"
    if isinstance(value, Keyword):
        pairs = [(key + ": ", item) for key, item in value]
        flat = "[" + ", ".join(key + elixir(item, inner) for key, item in pairs) + "]"
        if len(indent) + prefix + len(flat) <= 98:
            return flat
        items = (",\n" + inner).join(key + elixir(item, inner, len(key)) for key, item in pairs)
        return "[\n" + inner + items + "\n" + indent + "]"
    if isinstance(value, list):
        flat = "[" + ", ".join(elixir(item, inner) for item in value) + "]"
        if len(indent) + prefix + len(flat) <= 98:
            return flat
        items = (",\n" + inner).join(elixir(item, inner) for item in value)
        return "[\n" + inner + items + "\n" + indent + "]"
    if isinstance(value, dict):
        pairs = (",\n" + inner).join(
            key + ": " + elixir(item, inner, len(key) + 2) for key, item in value.items()
        )
        return "%{\n" + inner + pairs + "\n" + indent + "}"
    raise TypeError(type(value))


def hb_shape_version():
    result = subprocess.run(["hb-shape", "--version"], capture_output=True, text=True, check=True)
    package = subprocess.run(
        ["dpkg-query", "--show", "--showformat=${Version}", "libharfbuzz-bin"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()[0].split()[-1] + " (Debian " + package.stdout + ")"


entries = []
with tempfile.TemporaryDirectory() as scratch:
    for file in sorted(os.listdir(FONTS)):
        path = os.path.join(FONTS, file)
        for index in range(font_count(path)):
            entries.extend(shaped(path, file, index, scratch))

os.makedirs(os.path.dirname(TARGET), exist_ok=True)
with open(TARGET, "w") as output:
    output.write(
        "# Generated by test/support/ground_truth/shaping.py with hb-shape (HarfBuzz) "
        + hb_shape_version()
        + ", HarfBuzz "
        + uharfbuzz.version_string()
        + " through uharfbuzz "
        + uharfbuzz.__version__
        + " and fontTools "
        + fontTools.version
        + " on Python "
        + platform.python_version()
        + "; do not edit.\n"
    )
    output.write(elixir(entries) + "\n")
