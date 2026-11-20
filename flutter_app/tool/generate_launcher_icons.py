"""Zero-dependency Android launcher icon generator for Truth Lens Pro.

Generates sleek glowing neon AI Eye + Cyan/Purple Radar Ring PNG icons
directly into android/app/src/main/res/mipmap-*/ic_launcher.png.
"""

import math
import struct
import zlib
from pathlib import Path


def _write_png(path: Path, size: int, rgba_bytes: bytes) -> None:
    def _chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)  # PNG filter type 0
        start = y * stride
        raw.extend(rgba_bytes[start : start + stride])

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + _chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def _render_icon(size: int) -> bytes:
    buf = bytearray(size * size * 4)
    half = size / 2.0
    for py in range(size):
        ny = (py + 0.5 - half) / half  # -1..1
        for px in range(size):
            nx = (px + 0.5 - half) / half
            dist = math.hypot(nx, ny)
            angle = math.atan2(ny, nx)

            # Deep space radial background
            t_bg = max(0.0, min(1.0, 1.0 - dist * 0.85))
            r = 5.0 + 26.0 * t_bg
            g = 8.0 + 18.0 * t_bg
            b = 20.0 + 54.0 * t_bg
            a = 255.0

            # Outer dashed cyan radar ring
            if abs(dist - 0.80) < 0.032 and math.sin(angle * 6.0) > -0.25:
                r, g, b = 34.0, 211.0, 238.0

            # Inner purple radar arc
            if abs(dist - 0.68) < 0.025 and math.cos(angle * 3.0) > -0.1:
                r, g, b = 168.0, 85.0, 247.0

            # Futuristic AI Eye almond contour
            if abs(nx) <= 0.62:
                eye_y = 0.36 * math.cos((nx / 0.62) * (math.pi / 2.0))
                if abs(abs(ny) - eye_y) < 0.055:
                    mix = (nx + 0.62) / 1.24
                    r = 168.0 * (1.0 - mix) + 34.0 * mix
                    g = 85.0 * (1.0 - mix) + 211.0 * mix
                    b = 247.0 * (1.0 - mix) + 238.0 * mix

            # Glowing Cyan-Purple Iris
            if dist < 0.27:
                mix = max(0.0, min(1.0, dist / 0.27))
                r = 34.0 * (1.0 - mix) + 168.0 * mix
                g = 211.0 * (1.0 - mix) + 85.0 * mix
                b = 238.0 * (1.0 - mix) + 247.0 * mix

            # Dark Pupil
            if dist < 0.12:
                r, g, b = 4.0, 7.0, 18.0

            # Crisp white specular glint
            if math.hypot(nx - 0.09, ny + 0.09) < 0.048:
                r, g, b = 255.0, 255.0, 255.0

            # Soundwave accent at bottom
            if 0.56 <= ny <= 0.72 and abs(nx) <= 0.42:
                wave_h = 0.03 + 0.045 * abs(math.sin(nx * 24.0))
                if abs(ny - 0.64) <= wave_h:
                    r, g, b = 34.0, 211.0, 238.0

            idx = (py * size + px) * 4
            buf[idx] = int(max(0, min(255, r)))
            buf[idx + 1] = int(max(0, min(255, g)))
            buf[idx + 2] = int(max(0, min(255, b)))
            buf[idx + 3] = int(a)
    return bytes(buf)


def main() -> None:
    res_dir = Path("android/app/src/main/res")
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in densities.items():
        data = _render_icon(px)
        target = res_dir / folder / "ic_launcher.png"
        _write_png(target, px, data)
        round_target = res_dir / folder / "ic_launcher_round.png"
        if round_target.exists():
            _write_png(round_target, px, data)
    print("Generated Truth Lens Pro neon Android launcher icons cleanly.")


if __name__ == "__main__":
    main()
