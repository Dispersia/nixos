from __future__ import annotations

from .base import HORIZONTAL, VERTICAL, OcrRegion, bounding_box

_CJK_PREFIXES = ("ja", "zh", "ko")

_Box = tuple[float, float, float, float]

# Fallback spatial chaining (used when the provider has no block structure).
# A wrapped sentence continues in the next column/row of the same bubble, so the
# next line must sit very close and overlap almost entirely; anything looser
# merges separate bubbles.
_MAX_GAP = 0.6
_MIN_OVERLAP = 0.7
_CENTER_TOLERANCE = 0.6


def assign_sentences_from_blocks(
    regions: list[OcrRegion], blocks: list[tuple[list[list[float]], str]]
) -> bool:
    """Assign sentence text from the provider's own block (bubble) segmentation.

    Each block carries the full text of one block; every region is matched to the
    block it sits inside, and its offset is located within that block's text in
    reading order. Returns False when no region could be matched (so callers can
    fall back to spatial grouping).
    """
    if not regions or not blocks:
        return False

    prepared = []
    for polygon, text in blocks:
        box = bounding_box(polygon)
        if box is not None and text:
            prepared.append({"box": box, "text": text})

    if not prepared:
        return False

    members: dict[int, list[OcrRegion]] = {}
    for region in regions:
        box = bounding_box(region.polygon)
        index = _containing_block(box, prepared)
        if index is None:
            region.sentence = region.text
            region.sentence_offset = 0
            continue
        members.setdefault(index, []).append(region)

    if not members:
        return False

    for index, group in members.items():
        text = prepared[index]["text"]
        ordered = sorted(
            group,
            key=lambda region: _reading_key(bounding_box(region.polygon), region),
        )
        search_from = 0
        for region in ordered:
            region.sentence = text
            if region.text:
                found = text.find(region.text, search_from)
                if found < 0:
                    found = text.find(region.text)
                region.sentence_offset = found if found >= 0 else 0
                if found >= 0:
                    search_from = found + len(region.text)
            else:
                region.sentence_offset = 0
    return True


def assign_sentences(regions: list[OcrRegion], language: str | None = None) -> list[OcrRegion]:
    """Annotate each region with its full sentence and offset within it.

    Regions keep their own polygon/text (so the overlay can still render and
    hit-test them individually); this only groups them into sentences so a word
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
    lines = _cluster_lines(items, vertical=vertical, unit=unit)
    ordered = sorted(lines, key=lambda line: -line["center"] if vertical else line["center"])

    sentences: list[list[dict]] = []
    for line in ordered:
        if sentences and _continues(sentences[-1][-1], line, vertical=vertical, unit=unit):
            sentences[-1].append(line)
        else:
            sentences.append([line])

    for sentence in sentences:
        ordered_regions: list[OcrRegion] = []
        for line in sentence:
            ordered_regions.extend(region for region, _ in line["ordered"])
        texts = [region.text or "" for region in ordered_regions]
        full = separator.join(texts)
        offset = 0
        for region, text in zip(ordered_regions, texts, strict=True):
            region.sentence = full
            region.sentence_offset = offset
            offset += len(text) + len(separator)


def _cluster_lines(
    items: list[tuple[OcrRegion, _Box]], *, vertical: bool, unit: float
) -> list[dict]:
    tolerance = _CENTER_TOLERANCE * unit
    ordered = sorted(
        items,
        key=lambda item: (_center(item[1], vertical), _start(item[1], vertical)),
    )

    lines: list[dict] = []
    for region, box in ordered:
        center = _center(box, vertical)
        target = next((line for line in lines if abs(center - line["center"]) <= tolerance), None)
        if target is None:
            lines.append({"items": [(region, box)], "box": box, "center": center})
        else:
            target["items"].append((region, box))
            target["box"] = _union(target["box"], box)
            target["center"] = _center(target["box"], vertical)

    for line in lines:
        line["ordered"] = sorted(line["items"], key=lambda item: _start(item[1], vertical))
    return lines


def _continues(previous: dict, current: dict, *, vertical: bool, unit: float) -> bool:
    pbox = previous["box"]
    cbox = current["box"]

    if vertical:
        gap = pbox[0] - cbox[2]
        overlap = _overlap(pbox[1], pbox[3], cbox[1], cbox[3])
        extent = min(pbox[3] - pbox[1], cbox[3] - cbox[1])
    else:
        gap = cbox[1] - pbox[3]
        overlap = _overlap(pbox[0], pbox[2], cbox[0], cbox[2])
        extent = min(pbox[2] - pbox[0], cbox[2] - cbox[0])

    if gap < -0.5 * unit or gap > _MAX_GAP * unit:
        return False
    return extent > 0 and overlap >= _MIN_OVERLAP * extent


def _unit_size(items: list[tuple[OcrRegion, _Box]], *, vertical: bool) -> float:
    sizes = sorted((box[2] - box[0]) if vertical else (box[3] - box[1]) for _, box in items)
    return sizes[max(0, len(sizes) // 5)] or 1.0


def _center(box: _Box, vertical: bool) -> float:
    return (box[0] + box[2]) / 2 if vertical else (box[1] + box[3]) / 2


def _start(box: _Box, vertical: bool) -> float:
    return box[1] if vertical else box[0]


def _overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def _containing_block(box: _Box | None, blocks: list[dict]) -> int | None:
    if box is None:
        return None
    best: int | None = None
    best_area = 0.0
    for index, block in enumerate(blocks):
        area = _rect_overlap(box, block["box"])
        if area > best_area:
            best_area = area
            best = index
    return best


def _rect_overlap(a: _Box, b: _Box) -> float:
    width = min(a[2], b[2]) - max(a[0], b[0])
    height = min(a[3], b[3]) - max(a[1], b[1])
    if width <= 0 or height <= 0:
        return 0.0
    return width * height


def _reading_key(box: _Box | None, region: OcrRegion) -> tuple[float, float]:
    if box is None:
        return (0.0, 0.0)
    if region.direction == VERTICAL:
        return (-((box[0] + box[2]) / 2), box[1])
    return (box[1], box[0])


def _union(a: _Box, b: _Box) -> _Box:
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def _is_cjk(language: str | None) -> bool:
    if not language:
        return False
    return language.strip().lower().startswith(_CJK_PREFIXES)
