from __future__ import annotations

from .base import HORIZONTAL, VERTICAL, OcrRegion, bounding_box

_CJK_PREFIXES = ("ja", "zh", "ko")

_Box = tuple[float, float, float, float]

# A wrapped sentence continues in the next column/row of the same bubble: the
# next column must sit close by (small gap) and share almost the same vertical
# band. Anything looser merges separate bubbles that merely share an x-position.
_MAX_GAP = 0.6
_MIN_OVERLAP = 0.7


def assign_sentences(regions: list[OcrRegion], language: str | None = None) -> list[OcrRegion]:
    """Annotate each region with its full sentence and offset within it.

    Regions keep their own polygon/text (so the overlay can still render and
    hit-test them individually); this only groups them into bubbles so a word
    split across a wrapped column can be looked up in context.
    """
    if not regions:
        return regions

    separator = "" if _is_cjk(language) else " "
    vertical: list[tuple[OcrRegion, _Box]] = []
    horizontal: list[tuple[OcrRegion, _Box]] = []
    passthrough: list[OcrRegion] = []

    for region in regions:
        box = bounding_box(region.polygon)
        if box is None:
            passthrough.append(region)
        elif region.direction == VERTICAL:
            vertical.append((region, box))
        elif region.direction == HORIZONTAL:
            horizontal.append((region, box))
        else:
            passthrough.append(region)

    _assign_axis(vertical, vertical=True, separator=separator)
    _assign_axis(horizontal, vertical=False, separator=separator)
    for region in passthrough:
        region.sentence = region.text
        region.sentence_offset = 0
    return regions


def _assign_axis(items: list[tuple[OcrRegion, _Box]], *, vertical: bool, separator: str) -> None:
    if not items:
        return

    unit = _unit_size(items, vertical=vertical)
    for bubble in _group_bubbles(items, vertical=vertical, unit=unit):
        ordered = sorted(bubble["items"], key=lambda item: _reading_key(item[1], vertical))
        texts = [region.text or "" for region, _ in ordered]
        full = separator.join(texts)
        offset = 0
        for (region, _), text in zip(ordered, texts, strict=True):
            region.sentence = full
            region.sentence_offset = offset
            offset += len(text) + len(separator)


def _group_bubbles(
    items: list[tuple[OcrRegion, _Box]], *, vertical: bool, unit: float
) -> list[dict]:
    """Cluster regions into bubbles: near in the reading direction and sharing
    the perpendicular band. A column at the same x but a different height (a
    different bubble in the same panel) is kept separate."""
    ordered = sorted(
        items,
        key=lambda item: (_primary(item[1], vertical), _secondary(item[1], vertical)),
    )

    bubbles: list[dict] = []
    for region, box in ordered:
        target = None
        best = None
        for bubble in bubbles:
            gap = _gap(bubble["box"], box, vertical)
            if gap < -0.5 * unit or gap > _MAX_GAP * unit:
                continue
            if not _overlaps(bubble["box"], box, vertical):
                continue
            if best is None or abs(gap) < abs(best):
                best = gap
                target = bubble
        if target is None:
            bubbles.append({"box": box, "items": [(region, box)]})
        else:
            target["items"].append((region, box))
            target["box"] = _union(target["box"], box)
    return bubbles


def _gap(bubble: _Box, box: _Box, vertical: bool) -> float:
    # Distance from the bubble's near edge to the incoming column, along the
    # reading direction (right-to-left for vertical, top-to-bottom for horizontal).
    return bubble[0] - box[2] if vertical else box[1] - bubble[3]


def _overlaps(a: _Box, b: _Box, vertical: bool) -> bool:
    if vertical:
        overlap = _overlap(a[1], a[3], b[1], b[3])
        extent = min(a[3] - a[1], b[3] - b[1])
    else:
        overlap = _overlap(a[0], a[2], b[0], b[2])
        extent = min(a[2] - a[0], b[2] - b[0])
    return extent > 0 and overlap >= _MIN_OVERLAP * extent


def _unit_size(items: list[tuple[OcrRegion, _Box]], *, vertical: bool) -> float:
    sizes = sorted((box[2] - box[0]) if vertical else (box[3] - box[1]) for _, box in items)
    return sizes[max(0, len(sizes) // 5)] or 1.0


def _primary(box: _Box, vertical: bool) -> float:
    # Right-to-left for vertical (larger x first), top-to-bottom for horizontal.
    return -((box[0] + box[2]) / 2) if vertical else box[1]


def _secondary(box: _Box, vertical: bool) -> float:
    return box[1] if vertical else box[0]


def _reading_key(box: _Box, vertical: bool) -> tuple[float, float]:
    return (-((box[0] + box[2]) / 2), box[1]) if vertical else (box[1], box[0])


def _overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def _union(a: _Box, b: _Box) -> _Box:
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def _is_cjk(language: str | None) -> bool:
    if not language:
        return False
    return language.strip().lower().startswith(_CJK_PREFIXES)
