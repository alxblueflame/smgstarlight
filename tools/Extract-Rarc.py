import argparse
import pathlib
import struct


def be16(data, offset):
    return struct.unpack_from(">H", data, offset)[0]


def be32(data, offset):
    return struct.unpack_from(">I", data, offset)[0]


def yaz0(data):
    if data[:4] != b"Yaz0":
        return data
    output = bytearray()
    target_size = be32(data, 4)
    source = 16
    code = 0
    bits = 0
    while len(output) < target_size:
        if bits == 0:
            code = data[source]
            source += 1
            bits = 8
        if code & 0x80:
            output.append(data[source])
            source += 1
        else:
            pair = be16(data, source)
            source += 2
            distance = (pair & 0x0FFF) + 1
            length = pair >> 12
            if length == 0:
                length = data[source] + 0x12
                source += 1
            else:
                length += 2
            for _ in range(length):
                output.append(output[-distance])
                if len(output) == target_size:
                    break
        code <<= 1
        bits -= 1
    return bytes(output)


def safe_name(raw):
    return raw.decode("shift_jis", errors="replace").replace("/", "_").replace("\\", "_")


def extract(source, destination):
    data = yaz0(source.read_bytes())
    if data[:4] != b"RARC":
        raise ValueError("Input is not a Yaz0/RARC archive")
    info = 0x20
    data_base = info + be32(data, 0x0C)
    node_count = be32(data, info)
    node_base = info + be32(data, info + 4)
    entry_base = info + be32(data, info + 12)
    string_base = info + be32(data, info + 20)
    nodes = []
    for index in range(node_count):
        offset = node_base + index * 16
        nodes.append((be32(data, offset + 12), be16(data, offset + 10)))

    def string(offset):
        end = data.index(0, string_base + offset)
        return safe_name(data[string_base + offset:end])

    def walk(node_index, path, parents):
        first, count = nodes[node_index]
        for index in range(first, first + count):
            offset = entry_base + index * 20
            kind = be16(data, offset + 4)
            name = string(be16(data, offset + 6))
            item_offset = be32(data, offset + 8)
            item_size = be32(data, offset + 12)
            if kind & 0x0200:
                if name in (".", "..") or item_offset in parents:
                    continue
                walk(item_offset, path / name, parents | {node_index})
            else:
                target = path / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data[data_base + item_offset:data_base + item_offset + item_size])

    destination.mkdir(parents=True, exist_ok=True)
    walk(0, destination, set())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    extract(args.source, args.destination)
