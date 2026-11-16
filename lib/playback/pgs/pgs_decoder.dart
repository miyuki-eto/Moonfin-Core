// Adapted from Arcus92/libpgs-js (MIT, David Schulte). See LICENSE.
// Native Flutter cannot use its DOM canvas; this keeps the same SUP/PGS model.
import 'dart:typed_data';

class PgsBitmap {
  const PgsBitmap(this.x, this.y, this.width, this.height, this.rgba);
  final int x, y, width, height;
  final Uint8List rgba;
}

class PgsFrame {
  PgsFrame(this.at, this.width, this.height, this._objects, this._palette);
  final Duration at;
  final int width, height;
  final List<_PlacedObject> _objects;
  final Uint32List _palette;

  List<PgsBitmap> decode() {
    final pixels = _objects.fold<int>(
      0,
      (sum, entry) => sum + entry.object.width * entry.object.height,
    );
    if (pixels > 4096 * 2160) {
      throw const FormatException(
        'PGS composition exceeds bitmap memory limit',
      );
    }
    return [for (final object in _objects) object.decode(_palette)];
  }
}

class PgsTimeline {
  PgsTimeline(this.frames);
  final List<PgsFrame> frames;

  PgsFrame? at(Duration position) {
    var lo = 0, hi = frames.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (frames[mid].at <= position) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo == 0 ? null : frames[lo - 1];
  }
}

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  int get remaining => bytes.length - offset;
  int u8() {
    if (remaining < 1) throw const FormatException('Truncated PGS segment');
    return bytes[offset++];
  }

  int u16() => (u8() << 8) | u8();
  int u24() => (u8() << 16) | u16();
  int u32() => (u16() << 16) | u16();
  Uint8List take(int length) {
    if (length < 0 || remaining < length) {
      throw const FormatException('Truncated PGS data');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }
}

class _ObjectData {
  _ObjectData(this.width, this.height, this.expected);
  final int width, height, expected;
  final bytes = BytesBuilder(copy: false);
}

class _ImageObject {
  _ImageObject(this.width, this.height, this.data);
  final int width, height;
  final Uint8List data;
}

class _PlacedObject {
  _PlacedObject(this.object, this.x, this.y, this.crop);
  final _ImageObject object;
  final int x, y;
  final ({int x, int y, int width, int height})? crop;

  PgsBitmap decode(Uint32List palette) {
    final w = object.width, h = object.height;
    final indices = Uint8List(w * h);
    final r = _Reader(object.data);
    var x = 0, y = 0;
    while (r.remaining > 0 && y < h) {
      final first = r.u8();
      var count = 1, value = first;
      if (first == 0) {
        final flags = r.u8();
        if (flags == 0) {
          x = 0;
          y++;
          continue;
        }
        count = flags & 0x3f;
        if (flags & 0x40 != 0) count = (count << 8) | r.u8();
        value = flags & 0x80 != 0 ? r.u8() : 0;
      }
      if (count == 0 || x + count > w) {
        throw const FormatException('PGS run exceeds image row');
      }
      indices.fillRange(y * w + x, y * w + x + count, value);
      x += count;
    }
    final c = crop ?? (x: 0, y: 0, width: w, height: h);
    if (c.x < 0 ||
        c.y < 0 ||
        c.width <= 0 ||
        c.height <= 0 ||
        c.x + c.width > w ||
        c.y + c.height > h) {
      throw const FormatException('Invalid PGS crop');
    }
    final rgba = Uint8List(c.width * c.height * 4);
    for (var row = 0; row < c.height; row++) {
      for (var col = 0; col < c.width; col++) {
        final color = palette[indices[(row + c.y) * w + col + c.x]];
        final i = (row * c.width + col) * 4;
        if (color & 0xff == 0) continue;
        rgba[i] = color >> 24;
        rgba[i + 1] = color >> 16;
        rgba[i + 2] = color >> 8;
        rgba[i + 3] = color;
      }
    }
    return PgsBitmap(this.x + c.x, this.y + c.y, c.width, c.height, rgba);
  }
}

/// Keeps compressed images in the timeline. Only the currently displayed cue is
/// expanded to RGBA, rather than allocating full-screen images for a whole film.
PgsTimeline decodePgs(Uint8List bytes) {
  final r = _Reader(bytes);
  final palettes = <int, Uint32List>{};
  final images = <int, _ImageObject>{};
  final pending = <int, _ObjectData>{};
  final frames = <PgsFrame>[];
  var width = 0, height = 0, paletteId = 0;
  var at = Duration.zero;
  var placements =
      <
        ({int id, int x, int y, ({int x, int y, int width, int height})? crop})
      >[];
  var hasComposition = false;
  while (r.remaining > 0) {
    if (r.u16() != 0x5047) throw const FormatException('Invalid SUP magic');
    final pts = r.u32();
    r.u32(); // Decode timestamp; presentation follows PCS, including clear sets.
    final type = r.u8();
    final s = _Reader(r.take(r.u16()));
    switch (type) {
      case 0x16:
        width = s.u16();
        height = s.u16();
        if (width < 1 || height < 1 || width > 4096 || height > 2160) {
          throw const FormatException('Unsupported PGS display dimensions');
        }
        s.u8();
        s.u16();
        final state = s.u8();
        if (state != 0) {
          palettes.clear();
          images.clear();
          pending.clear();
        }
        s.u8();
        paletteId = s.u8();
        at = Duration(microseconds: (pts * 1000000 / 90000).round());
        placements = [];
        final count = s.u8();
        for (var i = 0; i < count; i++) {
          final id = s.u16();
          s.u8();
          final flags = s.u8(), x = s.u16(), y = s.u16();
          final crop = flags & 0x80 != 0
              ? (x: s.u16(), y: s.u16(), width: s.u16(), height: s.u16())
              : null;
          placements.add((id: id, x: x, y: y, crop: crop));
        }
        hasComposition = true;
      case 0x14:
        final id = s.u8();
        s.u8();
        final palette = Uint32List.fromList(palettes[id] ?? Uint32List(256));
        while (s.remaining > 0) {
          final index = s.u8(),
              y = s.u8(),
              cr = s.u8() - 128,
              cb = s.u8() - 128,
              a = s.u8();
          final red = (y + 1.402 * cr).round().clamp(0, 255);
          final green = (y - .34414 * cb - .71414 * cr).round().clamp(0, 255);
          final blue = (y + 1.772 * cb).round().clamp(0, 255);
          palette[index] = (red << 24) | (green << 16) | (blue << 8) | a;
        }
        palettes[id] = palette;
      case 0x15:
        final id = s.u16();
        s.u8();
        final flags = s.u8();
        if (flags & 0x80 != 0) {
          final expected = s.u24() - 4, w = s.u16(), h = s.u16();
          if (w < 1 ||
              h < 1 ||
              w * h > 4096 * 2160 ||
              expected < 0 ||
              expected > 32 * 1024 * 1024) {
            throw const FormatException(
              'Invalid PGS object dimensions or length',
            );
          }
          pending[id] = _ObjectData(w, h, expected);
        }
        final object = pending[id];
        if (object == null) {
          throw const FormatException(
            'PGS object continuation without a start',
          );
        }
        object.bytes.add(s.take(s.remaining));
        if (object.bytes.length > object.expected) {
          throw const FormatException('PGS object exceeds declared length');
        }
        if (flags & 0x40 != 0) {
          if (object.bytes.length != object.expected) {
            throw const FormatException('Truncated PGS object');
          }
          images[id] = _ImageObject(
            object.width,
            object.height,
            // A single ODS can be a view into the entire SUP buffer. Keep a
            // compact object so drawing one cue does not retain/transfer a film.
            Uint8List.fromList(object.bytes.takeBytes()),
          );
          pending.remove(id);
        }
      case 0x17: // Window definitions; composition coordinates are absolute.
        s.take(s.remaining);
      case 0x80:
        if (!hasComposition) {
          throw const FormatException('PGS display set has no composition');
        }
        final palette = palettes[paletteId];
        if (placements.isNotEmpty && palette == null) {
          throw const FormatException('Missing PGS palette');
        }
        final objects = <_PlacedObject>[];
        for (final p in placements) {
          final image = images[p.id];
          if (image == null) {
            throw const FormatException('Missing PGS image object');
          }
          objects.add(_PlacedObject(image, p.x, p.y, p.crop));
        }
        frames.add(
          PgsFrame(at, width, height, objects, palette ?? Uint32List(256)),
        );
        hasComposition = false;
      default:
        throw FormatException('Unsupported PGS segment $type');
    }
  }
  if (hasComposition || pending.isNotEmpty) {
    throw const FormatException('Incomplete PGS display set');
  }
  if (frames.isEmpty) throw const FormatException('Empty PGS subtitle track');
  for (var i = 1; i < frames.length; i++) {
    if (frames[i].at < frames[i - 1].at) {
      throw const FormatException('Unordered PGS timestamps');
    }
  }
  return PgsTimeline(frames);
}
