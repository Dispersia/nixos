from __future__ import annotations

from .base import HORIZONTAL, VERTICAL, OcrRegion, bounding_box

_CJK_PREFIXES = ("ja", "zh", "ko")


def _is_cjk(language: str | None) -> bool:
    if not language:
        return False
    return language.strip().lower().startswith(_CJK_PREFIXES)


def merge_line_regions(regions: list[OcrRegion], language: str | None = None) -> list[OcrRegion]:
    if len(regions) < 2:
        return regions

    separator = "" if _is_cjk(language) else " "
    vertical: list[tuple[OcrRegion, tuple[float, float, float, float]]] = []
    horizontal: list[tuple[OcrRegion, tuple[float, float, float, float]]] = []
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


def _merge_axis(
    items: list[tuple[OcrRegion, tuple[float, float, float, float]]],
    *,
    vertical: bool,
    separator: str,
) -> list[OcrRegion]:
    if len(items) < 2:
        return [region for region, _ in items]

    def size(box: tuple[float, float, float, float]) -> float:
        return (box[2] - box[0]) if vertical else (box[3] - box[1])

    def center(box: tuple[float, float, float, float]) -> float:
        return (box[0] + box[2]) / 2 if vertical else (box[1] + box[3]) / 2

    def start(box: tuple[float, float, float, float]) -> float:
        return box[1] if vertical else box[0]

    def end(box: tuple[float, float, float, float]) -> float:
        return box[3] if vertical else box[2]

    sizes = sorted(size(box) for _, box in items)
    unit = sizes[max(0, len(sizes) // 5)] or 1.0

    ordered = sorted(items, key=lambda item: (start(item[1]), center(item[1])))
    lines: list[dict] = []
    for region, box in ordered:
        target: dict | None = None
        for line in lines:
            if abs(center(box) - line["anchor"]) > 0.3 * unit:
                continue
            if abs(size(box) - line["size"]) > 1.0 * line["size"]:
                continue
            gap = start(box) - end(line["box"])
            if gap < 0 or gap > 0.25 * unit:
                continue
            if end(box) - line["start"] > 12.0 * unit:
                continue
            target = line
            break

        if target is None:
            lines.append(
                {
                    "items": [(region, box)],
                    "box": box,
                    "anchor": center(box),
                    "start": start(box),
                    "size": max(size(box), unit),
                }
            )
        else:
            target["items"].append((region, box))
            target["box"] = _union(target["box"], box)

    result: list[OcrRegion] = []
    for line in lines:
        members = sorted(line["items"], key=lambda item: start(item[1]))
        if len(members) == 1:
            result.append(members[0][0])
            continue

        text = separator.join(region.text for region, _ in members if region.text)
        confidences = [
            region.confidence for region, _ in members if region.confidence is not None
        ]
        left, top, right, bottom = line["box"]
        result.append(
            OcrRegion(
                polygon=[[left, top], [right, top], [right, bottom], [left, bottom]],
                text=text,
                confidence=sum(confidences) / len(confidences) if confidences else None,
                direction=VERTICAL if vertical else HORIZONTAL,
                language=members[0][0].language,
            )
        )
    return result


def _union(
    a: tuple[float, float, float, float], b: tuple[float, float, float, float]
) -> tuple[float, float, float, float]:
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))
