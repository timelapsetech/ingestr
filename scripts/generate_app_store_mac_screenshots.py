#!/usr/bin/env python3
"""
Composite Ingestr marketing screenshots into App Store Connect–ready Mac assets.

Apple Mac screenshots use a 16:10 aspect ratio. Per App Store Connect Help, you may provide
**only the highest-resolution** screenshots; Connect can scale them to other accepted sizes.

This script outputs **2880 × 1800** only (the largest listed Mac size).

Source image: docs/images/Ingestr_1_2_screenshot.png (required). Optional progress strip is unused; both slides use the main window only.

Visual style matches docs/ marketing pages (light gradient, cards, accent blue).

Run from repo root:
  python3 scripts/generate_app_store_mac_screenshots.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = Path(__file__).resolve().parents[1]
DOCS_IMAGES = REPO / "docs" / "images"
OUT_BASE = REPO / "marketing" / "app-store" / "screenshots"

# Largest accepted Mac App Store screenshot size (others are derived in App Store Connect).
OUTPUT_SIZE = (2880, 1800)

# docs/css/style.css — light theme
BG_TOP = (246, 247, 249)
BG_BOTTOM = (228, 232, 240)
TEXT = (26, 29, 33)
TEXT_MUTED = (92, 99, 112)
ACCENT = (10, 110, 189)  # --accent
ACCENT_SOFT = (219, 236, 252)  # tint for chips / blobs
CARD_BG = (255, 255, 255)
CARD_BORDER = (226, 229, 235)
BLOB = (10, 110, 189, 28)


def linear_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGB", (w, h))
    pixels = []
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        pixels.extend([(r, g, b)] * w)
    img.putdata(pixels)
    return img


def draw_decorative_layer(size: tuple[int, int]) -> Image.Image:
    """Soft accent blobs + subtle grid dots (marketing-page energy)."""
    w, h = size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    draw.ellipse((-w // 5, -h // 6, w // 2, h // 2), fill=BLOB)
    draw.ellipse((w - w // 3, h // 3, w + w // 4, h + h // 2), fill=BLOB)
    draw.ellipse((w // 2, -h // 8, w + w // 3, h // 3), fill=(10, 110, 189, 18))
    step = max(32, w // 90)
    dot = max(2, w // 720)
    for x in range(0, w, step):
        for y in range(0, h, step):
            draw.ellipse((x, y, x + dot, y + dot), fill=(92, 99, 112, 9))
    return layer


def get_font(px: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    names = (
        "SF Pro Display Bold.ttf" if bold else "SF Pro Display.ttf",
        "SFNSDisplay-Bold.otf" if bold else "SFNSDisplay.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    )
    for name in names:
        try:
            return ImageFont.truetype(name, px)
        except OSError:
            continue
    return ImageFont.load_default()


def scale_to_max(im: Image.Image, max_w: int, max_h: int) -> Image.Image:
    w, h = im.size
    scale = min(max_w / w, max_h / h, 1.0)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    if (nw, nh) == (w, h):
        return im.copy()
    return im.resize((nw, nh), Image.Resampling.LANCZOS)


def round_corners_rgba(im: Image.Image, radius: int) -> Image.Image:
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle((0, 0, im.width, im.height), radius=radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def paste_drop_shadow(
    canvas: Image.Image,
    im_rgba: Image.Image,
    xy: tuple[int, int],
    *,
    corner_radius: int,
    shadow_offset: tuple[int, int],
    blur: int,
    shadow_alpha: int = 70,
) -> None:
    w, h = im_rgba.size
    shadow_pad = blur * 3
    sw, sh = w + shadow_pad * 2, h + shadow_pad * 2
    shadow = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    r = corner_radius
    sdraw.rounded_rectangle(
        (shadow_pad, shadow_pad, shadow_pad + w, shadow_pad + h),
        radius=r,
        fill=(15, 25, 40, shadow_alpha),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    sx = xy[0] - shadow_pad + shadow_offset[0]
    sy = xy[1] - shadow_pad + shadow_offset[1]
    canvas.paste(shadow, (sx, sy), shadow)
    canvas.paste(im_rgba, xy, im_rgba)


def measure_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[float, float]:
    if hasattr(draw, "textbbox"):
        x0, y0, x1, y1 = draw.textbbox((0, 0), text, font=font)
        return (x1 - x0, y1 - y0)
    return (float(len(text) * 8), 16.0)


def wrap_lines(text: str, font: ImageFont.ImageFont, max_w: int, draw: ImageDraw.ImageDraw) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur: list[str] = []
    for w in words:
        trial = " ".join(cur + [w])
        tw, _ = measure_text(draw, trial, font)
        if cur and tw > max_w:
            lines.append(" ".join(cur))
            cur = [w]
        else:
            cur.append(w)
    if cur:
        lines.append(" ".join(cur))
    return lines


_DUMMY = Image.new("RGB", (8, 8))
_DUMMY_DRAW = ImageDraw.Draw(_DUMMY)


def layout_scale(w: int, h: int) -> float:
    return min(w / 2880.0, h / 1800.0)


def type_scale(s: float) -> float:
    return min(1.35, s + (1.0 - s) * 0.72)


def card_font_sizes(s: float, ts: float, k: float) -> tuple[int, int, int, int, int]:
    """title_px, body_px, pad, radius, bar_w — scaled by k to fill column height."""
    title_px = max(22, int(max(38, int(62 * ts)) * k))
    body_px = max(20, int(max(32, int(52 * ts)) * k))
    pad = max(18, int((26 * s + 8) * k))
    radius = max(10, int(16 * s * k))
    bar_w = max(5, int(8 * k))
    return title_px, body_px, pad, radius, bar_w


def card_text_column_width(max_w: int, pad: int, bar_w: int, scale: float) -> int:
    """
    Usable width for title + body inside a card (inside rounded rect, right of accent bar).
    Keeps wrapped text from extending past the card edge.
    """
    bar_gap = int(10 * scale)
    # left: pad | bar | gap | text ... text | pad
    inner = max_w - pad - bar_w - bar_gap - pad
    # small margin for font glyph overflow / subpixel rounding
    return max(28, inner - 6)


def measure_cards_intrinsic_height(
    cards: list[tuple[str, str]],
    max_w: int,
    scale: float,
    ts: float,
    k: float,
) -> int:
    """Total height of stacked cards + uniform gaps between them (gap = base_gap * k)."""
    title_px, body_px, pad, radius, bar_w = card_font_sizes(scale, ts, k)
    font_title = get_font(title_px, bold=True)
    font_body = get_font(body_px, bold=False)
    base_gap = int(18 * scale * k)
    col_w = card_text_column_width(max_w, pad, bar_w, scale)
    title_line_gap = max(2, int(4 * k))

    y = 0
    for i, (title, body) in enumerate(cards):
        title_lines = wrap_lines(title, font_title, col_w, _DUMMY_DRAW)
        body_lines = wrap_lines(body, font_body, col_w, _DUMMY_DRAW)
        th = 0.0
        for ti, tln in enumerate(title_lines):
            if ti:
                th += title_line_gap
            th += measure_text(_DUMMY_DRAW, tln, font_title)[1]
        line_gap = int(8 * ts * k)
        bh = sum(measure_text(_DUMMY_DRAW, ln, font_body)[1] for ln in body_lines)
        bh += max(0, len(body_lines) - 1) * line_gap
        inner_gap = int(10 * k)
        card_h = int(pad * 1.25 + th + inner_gap + bh + pad * 1.15)
        y += card_h
        if i < len(cards) - 1:
            y += base_gap
    return y


def best_card_scale_for_budget(
    cards: list[tuple[str, str]],
    max_w: int,
    scale: float,
    ts: float,
    budget: int,
) -> float:
    """Largest k such that intrinsic height <= budget (binary search)."""
    lo, hi = 0.45, 2.85
    best = lo
    for _ in range(28):
        mid = (lo + hi) / 2
        if measure_cards_intrinsic_height(cards, max_w, scale, ts, mid) <= budget:
            best = mid
            lo = mid
        else:
            hi = mid
    if measure_cards_intrinsic_height(cards, max_w, scale, ts, best) > budget:
        best = max(0.45, best * 0.92)
    return best


def draw_feature_cards_fill(
    img: Image.Image,
    x0: int,
    cards_top: int,
    col_bot: int,
    max_w: int,
    cards: list[tuple[str, str]],
    scale: float,
    ts: float,
) -> None:
    """Fill vertical space from cards_top to col_bot with scaled cards and equal slack gaps."""
    budget = max(0, col_bot - cards_top)
    n = len(cards)
    if n == 0 or budget < 8:
        return

    k = best_card_scale_for_budget(cards, max_w, scale, ts, budget)
    intrinsic = measure_cards_intrinsic_height(cards, max_w, scale, ts, k)
    slack = max(0, budget - intrinsic)
    # n+1 slots: above first card, between cards, below last
    slot = slack / float(n + 1)

    title_px, body_px, pad, radius, bar_w = card_font_sizes(scale, ts, k)
    font_title = get_font(title_px, bold=True)
    font_body = get_font(body_px, bold=False)
    base_gap = int(18 * scale * k)
    draw = ImageDraw.Draw(img, "RGBA")
    col_w = card_text_column_width(max_w, pad, bar_w, scale)
    title_line_gap = max(2, int(4 * k))

    y = cards_top + int(slot + 0.5)
    for i, (title, body) in enumerate(cards):
        title_lines = wrap_lines(title, font_title, col_w, draw)
        body_lines = wrap_lines(body, font_body, col_w, draw)
        th = 0.0
        for ti, tln in enumerate(title_lines):
            if ti:
                th += title_line_gap
            th += measure_text(draw, tln, font_title)[1]
        line_gap = int(8 * ts * k)
        bh = sum(measure_text(draw, ln, font_body)[1] for ln in body_lines)
        bh += max(0, len(body_lines) - 1) * line_gap
        inner_gap = int(10 * k)
        card_h = int(pad * 1.25 + th + inner_gap + bh + pad * 1.15)

        shadow = Image.new("RGBA", (max_w + 8, card_h + 8), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.rounded_rectangle((4, 4, max_w + 4, card_h + 4), radius=radius, fill=(0, 0, 0, 22))
        shadow = shadow.filter(ImageFilter.GaussianBlur(max(4, int(6 * scale))))
        img.paste(shadow, (x0 - 2, y - 2), shadow)

        draw.rounded_rectangle((x0, y, x0 + max_w, y + card_h), radius=radius, fill=CARD_BG + (255,), outline=CARD_BORDER, width=1)
        draw.rectangle((x0, y + int(card_h * 0.1), x0 + bar_w, y + int(card_h * 0.9)), fill=ACCENT)

        tx = x0 + pad + bar_w + int(10 * scale)
        ty = y + pad
        ty_title = ty
        for tln in title_lines:
            draw.text((tx, ty_title), tln, fill=TEXT, font=font_title)
            ty_title += int(measure_text(draw, tln, font_title)[1] + title_line_gap)
        ty2 = ty_title - title_line_gap + inner_gap
        for ln in body_lines:
            draw.text((tx, ty2), ln, fill=TEXT_MUTED, font=font_body)
            ty2 += int(measure_text(draw, ln, font_body)[1] + line_gap)

        y += card_h
        if i < n - 1:
            y += base_gap + int(slot + 0.5)
        else:
            y += int(slot + 0.5)


def draw_slide_1(canvas: Image.Image, main: Image.Image) -> None:
    w, h = canvas.size
    s = layout_scale(w, h)
    margin = int(44 * s)
    gap = int(32 * s)

    content_w = w - 2 * margin
    left_w = int(content_w * 0.36)
    right_w = content_w - left_w - gap
    x_left = margin
    x_right = margin + left_w + gap

    col_top = margin + int(8 * s)
    col_bot = h - margin
    col_h = col_bot - col_top

    ts = type_scale(s)
    draw = ImageDraw.Draw(canvas)
    brand_px = max(48, int(78 * ts))
    head_px = max(54, int(96 * ts))
    sub_px = max(36, int(58 * ts))
    font_brand = get_font(brand_px, bold=True)
    font_head = get_font(head_px, bold=True)
    font_sub = get_font(sub_px, bold=False)

    y = col_top
    draw.text((x_left, y), "Ingestr", fill=ACCENT, font=font_brand)
    y += int(brand_px * 1.1)
    headline = "Sort & rename sequences"
    draw.text((x_left, y), headline, fill=TEXT, font=font_head)
    y += int(head_px * 1.18)
    sub = "Built for time lapse, bursts, and big card dumps—right on your Mac."
    for line in wrap_lines(sub, font_sub, left_w, draw):
        draw.text((x_left, y), line, fill=TEXT_MUTED, font=font_sub)
        y += int(sub_px * 1.28)
    y += int(12 * s)

    cards = [
        ("Smart sequence detection", "Groups shots by capture time so mixed folders split sensibly."),
        ("Auto rename from EXIF", "Dated folders and consistent names from your camera metadata."),
        ("Extension filter & Add to existing", "Process only JPG or RAW, or append to a sequence already on disk."),
        ("Copy verification", "Optional size check or full byte-for-byte confirmation after copy."),
    ]
    draw_feature_cards_fill(canvas, x_left, y, col_bot, left_w, cards, s, ts)

    corner_r = int(18 * s)
    sh_blur = max(12, int(22 * s))
    sh_off = (int(18 * s), int(26 * s))

    max_w = right_w
    max_h = int(col_h * 0.995)
    scaled = scale_to_max(main, max_w, max_h)
    rounded = round_corners_rgba(scaled, corner_r)
    ix = x_right + (right_w - rounded.width) // 2
    iy = col_top + (col_h - rounded.height) // 2
    paste_drop_shadow(canvas, rounded, (ix, iy), corner_radius=corner_r, shadow_offset=sh_off, blur=sh_blur)

    chip_y = min(h - margin - int(36 * s), iy + rounded.height + int(14 * s))
    chip_text = "Drag folders · Set options · Start ingesting"
    chip_font = get_font(max(34, int(52 * ts)), bold=False)
    tw, th = measure_text(draw, chip_text, chip_font)
    cx0 = int(x_right + (right_w - tw) / 2)
    pad_x, pad_y = int(26 * s), int(15 * s)
    draw.rounded_rectangle(
        (cx0 - pad_x, chip_y - pad_y, cx0 + tw + pad_x, chip_y + th + pad_y),
        radius=int(15 * s),
        fill=ACCENT_SOFT + (255,),
        outline=CARD_BORDER,
        width=1,
    )
    draw.text((cx0, chip_y), chip_text, fill=ACCENT, font=chip_font)


def draw_slide_2(canvas: Image.Image, main: Image.Image) -> None:
    w, h = canvas.size
    s = layout_scale(w, h)
    margin = int(44 * s)
    gap = int(32 * s)
    content_w = w - 2 * margin
    left_w = int(content_w * 0.36)
    right_w = content_w - left_w - gap
    x_left = margin
    x_right = margin + left_w + gap

    col_top = margin + int(8 * s)
    col_bot = h - margin
    col_h = col_bot - col_top

    ts = type_scale(s)
    draw = ImageDraw.Draw(canvas)
    brand_px = max(48, int(78 * ts))
    head_px = max(54, int(96 * ts))
    sub_px = max(36, int(58 * ts))
    font_brand = get_font(brand_px, bold=True)
    font_head = get_font(head_px, bold=True)
    font_sub = get_font(sub_px, bold=False)

    y = col_top
    draw.text((x_left, y), "Ingestr", fill=ACCENT, font=font_brand)
    y += int(brand_px * 1.1)
    draw.text((x_left, y), "Stay in control on huge jobs", fill=TEXT, font=font_head)
    y += int(head_px * 1.18)
    sub = "Live progress, clear status text, and verification modes that match how careful you need to be."
    for line in wrap_lines(sub, font_sub, left_w, draw):
        draw.text((x_left, y), line, fill=TEXT_MUTED, font=font_sub)
        y += int(sub_px * 1.28)
    y += int(12 * s)

    cards = [
        ("Progress you can read", "Percent complete plus step-by-step detail while metadata and copies run."),
        ("Responsive window", "Large batches won’t freeze the UI—cancel anytime if plans change."),
        ("Verification modes", "None for speed, size-only for a light check, or full streaming hash for maximum confidence."),
    ]
    draw_feature_cards_fill(canvas, x_left, y, col_bot, left_w, cards, s, ts)

    corner_r = int(18 * s)
    sh_blur = max(12, int(22 * s))
    sh_off = (int(18 * s), int(26 * s))

    max_w = right_w
    max_h = int(col_h * 0.995)
    scaled = scale_to_max(main, max_w, max_h)
    rounded = round_corners_rgba(scaled, corner_r)
    ix = x_right + (right_w - rounded.width) // 2
    iy = col_top + (col_h - rounded.height) // 2
    paste_drop_shadow(canvas, rounded, (ix, iy), corner_radius=corner_r, shadow_offset=sh_off, blur=sh_blur)

    chip_y = min(h - margin - int(36 * s), iy + rounded.height + int(14 * s))
    chip_text = "Rename options · Copy verification · Clear feedback"
    chip_font = get_font(max(34, int(52 * ts)), bold=False)
    tw, th = measure_text(draw, chip_text, chip_font)
    cx0 = int(x_right + (right_w - tw) / 2)
    pad_x, pad_y = int(26 * s), int(15 * s)
    draw.rounded_rectangle(
        (cx0 - pad_x, chip_y - pad_y, cx0 + tw + pad_x, chip_y + th + pad_y),
        radius=int(15 * s),
        fill=ACCENT_SOFT + (255,),
        outline=CARD_BORDER,
        width=1,
    )
    draw.text((cx0, chip_y), chip_text, fill=ACCENT, font=chip_font)


def render_master(size: tuple[int, int], main: Image.Image) -> tuple[Image.Image, Image.Image]:
    w, h = size
    base = linear_gradient((w, h), BG_TOP, BG_BOTTOM).convert("RGBA")
    decor = draw_decorative_layer((w, h))
    base = Image.alpha_composite(base, decor)

    slide1 = base.copy()
    draw_slide_1(slide1, main)
    slide2 = base.copy()
    draw_slide_2(slide2, main)

    return slide1.convert("RGB"), slide2.convert("RGB")


def main() -> None:
    main_path = DOCS_IMAGES / "Ingestr_1_2_screenshot.png"
    if not main_path.is_file():
        raise SystemExit(f"Missing source image: {main_path}")

    main_im = Image.open(main_path).convert("RGBA")

    ow, oh = OUTPUT_SIZE
    s1, s2 = render_master((ow, oh), main_im)

    OUT_BASE.mkdir(parents=True, exist_ok=True)
    p1 = OUT_BASE / "01-main-window.png"
    p2 = OUT_BASE / "02-progress-and-status.png"
    s1.save(p1, "PNG", optimize=True)
    s2.save(p2, "PNG", optimize=True)
    print(f"Wrote {p1}")
    print(f"Wrote {p2}")


if __name__ == "__main__":
    main()
