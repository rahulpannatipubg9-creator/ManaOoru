"""Minimal Cloud-Optimized GeoTIFF window reader (Python standard library only).

Reads just the tiles a window needs, over HTTP range requests or from a local
file, so the import tools never download whole multi-hundred-MB rasters.
Supports tiled, chunky (interleaved) or planar TIFF/BigTIFF with no, deflate
or LZW compression, horizontal (2) or floating-point (3) predictors, and
8/16/32-bit integer or 32-bit float samples.
"""

import struct
import urllib.request
import zlib

TYPE_SIZES = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 16: 8, 17: 8, 18: 8}
TYPE_FORMATS = {1: "B", 2: "c", 3: "H", 4: "I", 6: "b", 7: "B", 8: "h", 9: "i", 11: "f", 12: "d", 16: "Q", 17: "q", 18: "Q"}


class CogReader:
    def __init__(self, source):
        self.source = source
        self._cache = {}
        head = self._read(0, 16)
        self.order = "<" if head[:2] == b"II" else ">"
        magic = struct.unpack(self.order + "H", head[2:4])[0]
        self.big = magic == 43
        offset = struct.unpack(self.order + ("Q" if self.big else "I"), head[8:16] if self.big else head[4:8])[0]
        self.ifds = []
        while offset:
            tags, offset = self._read_ifd(offset)
            self.ifds.append(tags)

    def _read(self, start, length):
        if self.source.startswith("http"):
            request = urllib.request.Request(self.source, headers={"Range": f"bytes={start}-{start + length - 1}"})
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        with open(self.source, "rb") as handle:
            handle.seek(start)
            return handle.read(length)

    def _read_ifd(self, offset):
        count_size, entry_size = (8, 20) if self.big else (2, 12)
        header = self._read(offset, count_size)
        count = struct.unpack(self.order + ("Q" if self.big else "H"), header)[0]
        block = self._read(offset + count_size, count * entry_size + (8 if self.big else 4))
        tags = {}
        for index in range(count):
            entry = block[index * entry_size:(index + 1) * entry_size]
            tag, kind = struct.unpack(self.order + "HH", entry[:4])
            if self.big:
                n = struct.unpack(self.order + "Q", entry[4:12])[0]
                inline, value_bytes = entry[12:20], 8
            else:
                n = struct.unpack(self.order + "I", entry[4:8])[0]
                inline, value_bytes = entry[8:12], 4
            size = TYPE_SIZES.get(kind, 1) * n
            if size <= value_bytes:
                data = inline[:size]
            else:
                pointer = struct.unpack(self.order + ("Q" if self.big else "I"), inline)[0]
                data = self._read(pointer, size)
            if kind == 2:
                tags[tag] = data.rstrip(b"\0").decode("latin-1")
            elif kind in (5, 10):
                parts = struct.unpack(self.order + ("I" if kind == 5 else "i") * (2 * n), data)
                tags[tag] = [parts[i] / parts[i + 1] for i in range(0, len(parts), 2)]
            else:
                tags[tag] = list(struct.unpack(self.order + TYPE_FORMATS.get(kind, "B") * n, data))
        tail = block[count * entry_size:]
        next_offset = struct.unpack(self.order + ("Q" if self.big else "I"), tail)[0]
        return tags, next_offset

    def geotransform(self):
        """(origin_x, pixel_width, origin_y, pixel_height) of the full-resolution image."""
        tags = self.ifds[0]
        scale = tags[33550]
        tie = tags[33922]
        return tie[3] - tie[0] * scale[0], scale[0], tie[4] + tie[1] * scale[1], -scale[1]

    def size(self, level=0):
        tags = self.ifds[level]
        return tags[256][0], tags[257][0]

    def read_window(self, x0, y0, width, height, band=0, level=0):
        """Returns rows (lists of floats) for the pixel window at the given overview level."""
        tags = self.ifds[level]
        tile_w, tile_h = tags[322][0], tags[323][0]
        image_w, image_h = tags[256][0], tags[257][0]
        samples = tags.get(277, [1])[0]
        planar = tags.get(284, [1])[0]
        bits = tags[258][0]
        sample_format = tags.get(339, [1])[0]
        compression = tags.get(259, [1])[0]
        predictor = tags.get(317, [1])[0]
        offsets, counts = tags[324], tags[325]
        tiles_across = (image_w + tile_w - 1) // tile_w
        tiles_down = (image_h + tile_h - 1) // tile_h
        code = {(1, 8): "B", (1, 16): "H", (1, 32): "I", (2, 8): "b", (2, 16): "h", (2, 32): "i", (3, 32): "f"}[(sample_format, bits)]
        per_tile_samples = 1 if planar == 2 else samples
        out = [[0.0] * width for _ in range(height)]
        for tile_y in range(max(0, y0 // tile_h), min(tiles_down, (y0 + height - 1) // tile_h + 1)):
            for tile_x in range(max(0, x0 // tile_w), min(tiles_across, (x0 + width - 1) // tile_w + 1)):
                index = tile_y * tiles_across + tile_x
                if planar == 2:
                    index += band * tiles_across * tiles_down
                values = self._tile(offsets[index], counts[index], compression, predictor, code, bits,
                                    tile_w, tile_h, per_tile_samples)
                channel = 0 if planar == 2 else band
                for row in range(tile_h):
                    y = tile_y * tile_h + row - y0
                    if not 0 <= y < height:
                        continue
                    for col in range(tile_w):
                        x = tile_x * tile_w + col - x0
                        if 0 <= x < width:
                            out[y][x] = values[(row * tile_w + col) * per_tile_samples + channel]
        return out

    def _tile(self, offset, count, compression, predictor, code, bits, tile_w, tile_h, samples):
        key = (offset, count)
        if key in self._cache:
            return self._cache[key]
        raw = self._read(offset, count) if count else b""
        if compression == 8 or compression == 32946:
            raw = zlib.decompress(raw)
        elif compression == 5:
            raw = _lzw_decode(raw)
        elif compression != 1:
            raise ValueError(f"Unsupported TIFF compression {compression}")
        byte_width = bits // 8
        expected = tile_w * tile_h * samples * byte_width
        raw = raw[:expected].ljust(expected, b"\0")
        if predictor == 3:
            raw = _undo_float_predictor(raw, tile_w, tile_h, samples, byte_width)
            values = list(struct.unpack(self.order + code * (len(raw) // byte_width), raw))
        else:
            values = list(struct.unpack(self.order + code * (len(raw) // byte_width), raw))
            if predictor == 2:
                mask = (1 << bits) - 1 if code.isupper() else None
                for row in range(tile_h):
                    base = row * tile_w * samples
                    for col in range(1, tile_w):
                        for s in range(samples):
                            i = base + col * samples + s
                            values[i] = values[i] + values[i - samples]
                            if mask is not None:
                                values[i] &= mask
        if len(self._cache) > 256:
            self._cache.clear()
        self._cache[key] = values
        return values


def _undo_float_predictor(raw, width, height, samples, byte_width):
    row_bytes = width * samples * byte_width
    out = bytearray(len(raw))
    for row in range(height):
        data = bytearray(raw[row * row_bytes:(row + 1) * row_bytes])
        for i in range(1, row_bytes):
            data[i] = (data[i] + data[i - 1]) & 0xFF
        count = width * samples
        for i in range(count):
            for b in range(byte_width):
                out[row * row_bytes + i * byte_width + (byte_width - 1 - b)] = data[b * count + i]
    return bytes(out)


def _lzw_decode(data):
    table = [bytes([i]) for i in range(256)] + [b"", b""]
    out = bytearray()
    bit_pos, code_len, previous = 0, 9, None
    total_bits = len(data) * 8
    while bit_pos + code_len <= total_bits:
        byte = bit_pos >> 3
        chunk = int.from_bytes(data[byte:byte + 4].ljust(4, b"\0"), "big")
        code = (chunk >> (32 - (bit_pos & 7) - code_len)) & ((1 << code_len) - 1)
        bit_pos += code_len
        if code == 256:
            table = table[:258]
            code_len, previous = 9, None
            continue
        if code == 257:
            break
        if previous is None:
            entry = table[code]
        elif code < len(table):
            entry = table[code]
            table.append(previous + entry[:1])
        else:
            entry = previous + previous[:1]
            table.append(entry)
        out += entry
        previous = entry
        if len(table) + 1 >= (1 << code_len) and code_len < 12:
            code_len += 1
    return bytes(out)
