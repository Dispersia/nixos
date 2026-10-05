from __future__ import annotations

from .base import HORIZONTAL, VERTICAL, OcrRegion, bounding_box

_CJK_PREFIXES = ("ja", "zh", "ko")

_Box = tuple[float, float, float, float]


def _is_cjk(language: str | None) -> bool:
    if not language:
        return False
    return language.strip().lower().startswith(_CJK_PREFIXES)


def merge_line_regions(regions: list[OcrRegion], language: str | None = None) -> list[OcrRegion]:
    if len(regions) < 2:
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

    merged = _merge_axis(vertical, vertical=True, separator=separator)
    merged += _merge_axis(horizontal, vertical=False, separator=separator)
    return merged + passthrough


def _box_size(box: _Box, vertical: bool) -> float:
    return (box[2] - box[0]) if vertical else (box[3] - box[1])


def _box_center(box: _Box, vertical: bool) -> float:
    return (box[0] + box[2]) / 2 if vertical else (box[1] + box[3]) / 2


def _box_start(box: _Box, vertical: bool) -> float:
    return box[1] if vertical else box[0]


def _box_end(box: _Box, vertical: bool) -> float:
    return box[3] if vertical else box[2]


def _unit_size(items: list[tuple[OcrRegion, _Box]], vertical: bool) -> float:
    sizes = sorted(_box_size(box, vertical) for _, box in items)
    return sizes[max(0, len(sizes) // 5)] or 1.0


def _merge_axis(
    items: list[tuple[OcrRegion, _Box]],
    *,
    vertical: bool,
    separator: str,
) -> list[OcrRegion]:
    if len(items) < 2:
        return [region for region, _ in items]

    unit = _unit_size(items, vertical)
    lines = _group_lines(items, vertical=vertical, unit=unit)
    return [_line_to_region(line, vertical=vertical, separator=separator) for line in lines]


def _group_lines(
    items: list[tuple[OcrRegion, _Box]],
    *,
    vertical: bool,
    unit: float,
) -> list[dict]:
    ordered = sorted(
        items,
        key=lambda item: (_box_start(item[1], vertical), _box_center(item[1], vertical)),
    )

    lines: list[dict] = []
    for region, box in ordered:
        target = _find_line(lines, box, vertical=vertical, unit=unit)
        if target is None:
            lines.append(_new_line(region, box, vertical=vertical, unit=unit))
        else:
            target["items"].append((region, box))
            target["box"] = _union(target["box"], box)
    return lines


def _find_line(
    lines: list[dict],
    box: _Box,
    *,
    vertical: bool,
    unit: float,
) -> dict | None:
    for line in lines:
        if _fits_line(line, box, vertical=vertical, unit=unit):
            return line
    return None


def _fits_line(line: dict, box: _Box, *, vertical: bool, unit: float) -> bool:
    if abs(_box_center(box, vertical) - line["anchor"]) > 0.3 * unit:
        return False
    if abs(_box_size(box, vertical) - line["size"]) > 1.0 * line["size"]:
        return False
    gap = _box_start(box, vertical) - _box_end(line["box"], vertical)
    if gap < 0 or gap > 0.25 * unit:
        return False
    return _box_end(box, vertical) - line["start"] <= 12.0 * unit


def _new_line(region: OcrRegion, box: _Box, *, vertical: bool, unit: float) -> dict:
    return {
        "items": [(region, box)],
        "box": box,
        "anchor": _box_center(box, vertical),
        "start": _box_start(box, vertical),
        "size": max(_box_size(box, vertical), unit),
    }


def _line_to_region(line: dict, *, vertical: bool, separator: str) -> OcrRegion:
    members = sorted(line["items"], key=lambda item: _box_start(item[1], vertical))
    if len(members) == 1:
        return members[0][0]

    text = separator.join(region.text for region, _ in members if region.text)
    confidences = [region.confidence for region, _ in members if region.confidence is not None]
    left, top, right, bottom = line["box"]
    return OcrRegion(
        polygon=[[left, top], [right, top], [right, bottom], [left, bottom]],
        text=text,
        confidence=sum(confidences) / len(confidences) if confidences else None,
        direction=VERTICAL if vertical else HORIZONTAL,
        language=members[0][0].language,
    )


def _union(a: _Box, b: _Box) -> _Box:
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))
