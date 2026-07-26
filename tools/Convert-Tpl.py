import argparse
import pathlib
import struct

from PIL import Image


def be16(data, offset):
    return struct.unpack_from(">H", data, offset)[0]


def be32(data, offset):
    return struct.unpack_from(">I", data, offset)[0]


def expand(value, bits):
    maximum = (1 << bits) - 1
    return (value * 255 + maximum // 2) // maximum


def decode_pixel(value, fmt):
    if fmt == 4:
        return (expand(value >> 11, 5), expand((value >> 5) & 63, 6), expand(value & 31, 5), 255)
    if fmt == 5:
        if value & 0x8000:
            return (expand((value >> 10) & 31, 5), expand((value >> 5) & 31, 5),
                    expand(value & 31, 5), 255)
        return (expand((value >> 8) & 15, 4), expand((value >> 4) & 15, 4),
                expand(value & 15, 4), expand((value >> 12) & 7, 3))
    raise ValueError(f"Unsupported 16-bit TPL format {fmt}")


def convert(source, destination):
    data = source.read_bytes()
    if be32(data, 0) != 0x0020AF30 or be32(data, 4) != 1:
        raise ValueError("Expected a single-image TPL")
    table = be32(data, 8)
    header = be32(data, table)
    height = be16(data, header)
    width = be16(data, header + 2)
    fmt = be32(data, header + 4)
    offset = be32(data, header + 8)
    pixels = [(0, 0, 0, 0)] * (width * height)
    cursor = offset
    if fmt == 1:
        block_width, block_height = 8, 4
        for by in range(0, height, block_height):
            for bx in range(0, width, block_width):
                for y in range(block_height):
                    for x in range(block_width):
                        intensity = data[cursor]
                        cursor += 1
                        px, py = bx + x, by + y
                        if px < width and py < height:
                            pixels[py * width + px] = (intensity, intensity, intensity, 255)
    elif fmt in (4, 5):
        block_width = block_height = 4
        for by in range(0, height, block_height):
            for bx in range(0, width, block_width):
                for y in range(block_height):
                    for x in range(block_width):
                        value = be16(data, cursor)
                        cursor += 2
                        px, py = bx + x, by + y
                        if px < width and py < height:
                            pixels[py * width + px] = decode_pixel(value, fmt)
    else:
        raise ValueError(f"Unsupported TPL format {fmt}")
    image = Image.new("RGBA", (width, height))
    image.putdata(pixels)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    convert(args.source, args.destination)
