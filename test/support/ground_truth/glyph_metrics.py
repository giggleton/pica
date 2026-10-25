# Writes test/fixtures/glyph_metrics.exs: what fontTools reads for every glyph of each test font,
# which is what `Pica.nominal_advances/2`, `Pica.glyph_boxes/2` and `Pica.glyph_ids/2` must
# report.
#
# Run from the repository root:
#
#   docker run --rm -v "$PWD":/work -w /work -e OWNER="$(id -u):$(id -g)" python:3.12-slim sh -c \
#     'pip install --quiet fonttools==4.67.0 brotli==1.2.0 \
#      && python -I test/support/ground_truth/glyph_metrics.py \
#      && chown "$OWNER" test/fixtures/glyph_metrics.exs'
#
# Rerun it when a test font changes. For each glyph, by glyph id:
#
#   * advances: the glyph's advance width in hmtx.
#   * boxes: the glyph's control box at the font's default location: the box around every point
#     of its outline, on-curve and off, which is what FreeType computes. A glyph with no outline,
#     such as a space, has no box (:none).
#       - TrueType (glyf): the box of the glyph's points, as fontTools composes them, each rounded
#         to the nearest font unit first. A composite glyph that scales a component lands its
#         points between units; FreeType, loading a glyph unscaled, multiplies in whole units and
#         so rounds each point, and skrifa does the same.
#       - CFF and CFF2: fontTools' ControlBoundsPen, with a corner that falls between font units
#         rounded outward (the minimums down, the maximums up).
#
# And for one text per font, the glyph each character maps to through the font's best Unicode
# character map, 0 for a character the font lacks.

import math
import os
import platform

import fontTools
from fontTools.misc.roundTools import otRound
from fontTools.pens.boundsPen import ControlBoundsPen
from fontTools.ttLib import TTFont

FONTS = "test/fonts"
TARGET = "test/fixtures/glyph_metrics.exs"

# Capitals, a space, descenders, an accented letter, the black star (U+2605) and the mathematical
# bold capital A (U+1D400), past the Basic Multilingual Plane.
TEXT = "AVM gjpqyQ é★\U0001d400"

SIGNATURES = (b"\x00\x01\x00\x00", b"true", b"OTTO", b"ttcf", b"wOFF", b"wOF2")


def font_count(path):
    with open(path, "rb") as file:
        header = file.read(12)
    if header[0:4] not in SIGNATURES:
        return 0  # a licence or FONTS.md
    if header[0:4] != b"ttcf":
        return 1
    return int.from_bytes(header[8:12], "big")


def truetype_box(glyf, name):
    coordinates, _end_points, _flags = glyf[name].getCoordinates(glyf)
    if len(coordinates) == 0:
        return Atom("none")
    xs = [otRound(x) for x, _y in coordinates]
    ys = [otRound(y) for _x, y in coordinates]
    return (min(xs), min(ys), max(xs), max(ys))


def cff_box(glyph_set, name):
    pen = ControlBoundsPen(glyph_set)
    glyph_set[name].draw(pen)
    if pen.bounds is None:
        return Atom("none")
    x_min, y_min, x_max, y_max = pen.bounds
    return (math.floor(x_min), math.floor(y_min), math.ceil(x_max), math.ceil(y_max))


def metrics(path, index):
    font = TTFont(path, fontNumber=index)
    order = font.getGlyphOrder()
    glyph_set = font.getGlyphSet()
    hmtx = font["hmtx"]
    cmap = font.getBestCmap()
    glyph_ids = [font.getGlyphID(cmap[ord(character)]) if ord(character) in cmap else 0
                 for character in TEXT]
    return {
        "file": os.path.basename(path),
        "index": index,
        "text": TEXT,
        "glyph_ids": glyph_ids,
        "advances": [hmtx[name][0] for name in order],
        "boxes": [
            truetype_box(font["glyf"], name) if "glyf" in font else cff_box(glyph_set, name)
            for name in order
        ],
    }


class Atom(str):
    pass


# Elixir terms laid out as `mix format` lays them out, so the formatter leaves the file alone: a
# collection that does not fit on its line puts each element on a line of its own.
def elixir(value, indent="", prefix=0):
    inner = indent + "  "
    if isinstance(value, Atom):
        return ":" + value
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
        entries.append(metrics(path, index))

os.makedirs(os.path.dirname(TARGET), exist_ok=True)
with open(TARGET, "w") as output:
    output.write(
        "# Generated by test/support/ground_truth/glyph_metrics.py with fontTools "
        + fontTools.version
        + " on Python "
        + platform.python_version()
        + "; do not edit.\n"
    )
    output.write(elixir(entries) + "\n")
