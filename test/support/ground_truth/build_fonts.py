# Builds the test fonts that are made rather than downloaded, both from Roboto[wdth,wght].ttf:
#
#   * test/fonts/Roboto-Collection.ttc — a font collection holding Roboto as it is and its bold
#     instance (wght 700, wdth 100), cut by fontTools' instancer and renamed to match.
#   * test/fonts/Roboto-Bare.ttf — Roboto with its OS/2 table and its family and subfamily names
#     (name IDs 1, 2, 16 and 17) removed, and its head table marked italic, for the values a
#     font may lack.
#
# Run from the repository root:
#
#   docker run --rm -v "$PWD":/work -w /work -e OWNER="$(id -u):$(id -g)" python:3.12-slim sh -c \
#     'pip install --quiet fonttools==4.67.0 && python -I test/support/ground_truth/build_fonts.py \
#      && chown "$OWNER" test/fonts/Roboto-Collection.ttc test/fonts/Roboto-Bare.ttf'
#
# Roboto is built from because its licence reserves no font name, so a font derived from it may
# keep the name; every other test font reserves its name. Rerun this when Roboto[wdth,wght].ttf
# changes, then rerun font_info.py and update test/fonts/FONTS.md.

from fontTools.ttLib import TTFont
from fontTools.ttLib.ttCollection import TTCollection
from fontTools.varLib import instancer

SOURCE = "test/fonts/Roboto[wdth,wght].ttf"

# recalcTimestamp=False keeps the head table's dates, so a rebuild writes the same bytes.
variable = TTFont(SOURCE, recalcTimestamp=False)
bold = instancer.instantiateVariableFont(
    TTFont(SOURCE, recalcTimestamp=False), {"wght": 700, "wdth": 100}, updateFontNames=True
)

collection = TTCollection()
collection.fonts = [variable, bold]
collection.save("test/fonts/Roboto-Collection.ttc", shareTables=True)

bare = TTFont(SOURCE, recalcTimestamp=False)
del bare["OS/2"]
bare["name"].names = [
    record for record in bare["name"].names if record.nameID not in (1, 2, 16, 17)
]
bare["head"].macStyle |= 2
bare.save("test/fonts/Roboto-Bare.ttf")
