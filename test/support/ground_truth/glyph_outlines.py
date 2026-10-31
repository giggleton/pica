# Writes test/fixtures/glyph_outlines.exs: what fontTools draws for a sample of each test font's
# glyphs, which is what `Pica.glyph_outlines/2` must draw.
#
# Run from the repository root:
#
#   docker run --rm -v "$PWD":/work -w /work -e OWNER="$(id -u):$(id -g)" python:3.12-slim sh -c \
#     'pip install --quiet fonttools==4.67.0 brotli==1.2.0 \
#      && python -I test/support/ground_truth/glyph_outlines.py \
#      && chown "$OWNER" test/fixtures/glyph_outlines.exs'
#
# Rerun it when a test font changes. For each font, the glyphs drawn are, each with its reasons:
#
#   * the glyph each character of glyph_metrics.py's text and the digits maps to through the
#     font's best Unicode character map, 0 for a character the font lacks;
#   * glyph 0, .notdef;
#   * in a TrueType font, every composite glyph that scales a component, every glyph with a
#     contour that has no point on the curve, and the first ten glyphs with a contour that starts
#     off the curve, the kinds where drawing a point stream takes a rule.
#
# Each glyph is drawn at the font's default location into a pen that records fontTools' segments,
# quadratic runs split at their implied on-curve points (BasePen's own splitting, including a
# contour with no point on the curve). A glyph with no outline, such as a space, draws :none.
#   - TrueType (glyf): the glyph's points, as fontTools composes them, each rounded to the nearest
#     font unit first, then drawn by fontTools' own glyf drawing. A composite glyph that scales a
#     component lands its points between units; FreeType, loading a glyph unscaled, multiplies in
#     whole units and so rounds each point, and skrifa does the same.
#   - CFF and CFF2: the charstring as fontTools draws it, coordinates unrounded.
#
# fontTools starts a contour whose first point is off the curve at its first point on the curve,
# where FreeType, and skrifa, start it at its last point, or between its last and first; the tests
# compare each contour as a closed loop, wherever it starts.

import os
import platform

import fontTools
from fontTools.misc.roundTools import otRound
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates, flagOnCurve

FONTS = "test/fonts"
TARGET = "test/fixtures/glyph_outlines.exs"

# glyph_metrics.py's text: capitals, a space, descenders, an accented letter, the black star
# (U+2605) and the mathematical bold capital A (U+1D400), past the Basic Multilingual Plane; then
# the digits.
TEXT = "AVM gjpqyQ é★\U0001d400" + "0123456789"

OFF_CURVE_STARTS = 10

SIGNATURES = (b"\x00\x01\x00\x00", b"true", b"OTTO", b"ttcf", b"wOFF", b"wOF2")


def font_count(path):
    with open(path, "rb") as file:
        header = file.read(12)
    if header[0:4] not in SIGNATURES:
        return 0  # a licence or FONTS.md
    if header[0:4] != b"ttcf":
        return 1
    return int.from_bytes(header[8:12], "big")


class RecordingPen(BasePen):
    def __init__(self, glyph_set):
        super().__init__(glyph_set)
        self.commands = []

    def _moveTo(self, point):
        self.commands.append((Atom("move"), *point))

    def _lineTo(self, point):
        self.commands.append((Atom("line"), *point))

    def _qCurveToOne(self, control, point):
        self.commands.append((Atom("quad"), *control, *point))

    def _curveToOne(self, first_control, second_control, point):
        self.commands.append((Atom("cubic"), *first_control, *second_control, *point))

    def _closePath(self):
        self.commands.append(Atom("close"))

    def _endPath(self):
        raise ValueError("an open contour")


def floats(commands):
    return [
        command if isinstance(command, Atom) else (command[0], *(float(value) for value in command[1:]))
        for command in commands
    ]


def truetype_outline(glyf, name):
    coordinates, end_points, flags = glyf[name].getCoordinates(glyf)
    if len(coordinates) == 0:
        return Atom("none")
    rounded = Glyph()
    rounded.numberOfContours = len(end_points)
    rounded.coordinates = GlyphCoordinates([(otRound(x), otRound(y)) for x, y in coordinates])
    rounded.endPtsOfContours = list(end_points)
    rounded.flags = bytearray(flags)
    pen = RecordingPen(None)
    rounded.draw(pen, glyf)
    return floats(pen.commands)


def cff_outline(glyph_set, name):
    pen = RecordingPen(glyph_set)
    glyph_set[name].draw(pen)
    if not pen.commands:
        return Atom("none")
    return floats(pen.commands)


def contours(glyf, name):
    _coordinates, end_points, flags = glyf[name].getCoordinates(glyf)
    start = 0
    for end in end_points:
        yield [flag & flagOnCurve for flag in flags[start : end + 1]]
        start = end + 1


def rare_kinds(font):
    """The glyph ids of each kind of TrueType glyph whose drawing takes a rule, with its reason."""
    if "glyf" not in font:
        return []
    glyf = font["glyf"]
    kinds = []
    off_curve_starts = 0
    for glyph_id, name in enumerate(font.getGlyphOrder()):
        glyph = glyf[name]
        if glyph.isComposite() and any(hasattr(component, "transform") for component in glyph.components):
            kinds.append((glyph_id, "a composite that scales a component"))
        on_curve = list(contours(glyf, name))
        if any(not any(flags) for flags in on_curve):
            kinds.append((glyph_id, "a contour with no point on the curve"))
        if off_curve_starts < OFF_CURVE_STARTS and any(flags and not flags[0] for flags in on_curve):
            off_curve_starts += 1
            kinds.append((glyph_id, "a contour that starts off the curve"))
    return kinds


def outlines(path, index):
    font = TTFont(path, fontNumber=index)
    order = font.getGlyphOrder()
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()

    reasons = {0: [".notdef"]}
    for character in TEXT:
        glyph_id = font.getGlyphID(cmap[ord(character)]) if ord(character) in cmap else 0
        reasons.setdefault(glyph_id, []).append('the character "' + character + '"')
    for glyph_id, reason in rare_kinds(font):
        reasons.setdefault(glyph_id, []).append(reason)

    def outline(name):
        if "glyf" in font:
            return truetype_outline(font["glyf"], name)
        return cff_outline(glyph_set, name)

    return {
        "file": os.path.basename(path),
        "index": index,
        "glyphs": [
            {"glyph_id": glyph_id, "reasons": reasons[glyph_id], "outline": outline(order[glyph_id])}
            for glyph_id in sorted(reasons)
        ],
    }


class Atom(str):
    pass


# A float as Elixir writes one: always a fraction, and an exponent only after one.
def elixir_float(value):
    text = repr(value)
    if "e" not in text:
        return text
    mantissa, exponent = text.split("e")
    if "." not in mantissa:
        mantissa += ".0"
    return mantissa + "e" + str(int(exponent))


# Elixir terms laid out as `mix format` lays them out, so the formatter leaves the file alone: a
# collection that does not fit on its line puts each element on a line of its own.
def elixir(value, indent="", prefix=0):
    inner = indent + "  "
    if isinstance(value, Atom):
        return ":" + value
    if isinstance(value, float):
        return elixir_float(value)
    if isinstance(value, int):
        return repr(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("#{", "\\#{")
        return '"' + escaped + '"'
    if isinstance(value, tuple):
        return "{" + ", ".join(elixir(item) for item in value) + "}"
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


entries = []
for file in sorted(os.listdir(FONTS)):
    path = os.path.join(FONTS, file)
    for index in range(font_count(path)):
        entries.append(outlines(path, index))

os.makedirs(os.path.dirname(TARGET), exist_ok=True)
with open(TARGET, "w") as output:
    output.write(
        "# Generated by test/support/ground_truth/glyph_outlines.py with fontTools "
        + fontTools.version
        + " on Python "
        + platform.python_version()
        + "; do not edit.\n"
    )
    output.write(elixir(entries) + "\n")
