import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/pgs/pgs_decoder.dart';

void main() {
  final bytes = File('test/fixtures/pgs/libpgs.sup').readAsBytesSync();
  test('matches libpgs reference RGBA for all authored sample frames', () {
    final track = decodePgs(bytes);
    for (var i = 0; i < 3; i++) {
      final frame = track.at(Duration(milliseconds: 1500 + i * 1000))!;
      final actual = Uint8List(frame.width * frame.height * 4);
      for (final bitmap in frame.decode()) {
        for (var y = 0; y < bitmap.height; y++) {
          final destination = ((y + bitmap.y) * frame.width + bitmap.x) * 4;
          actual.setRange(
            destination,
            destination + bitmap.width * 4,
            bitmap.rgba,
            y * bitmap.width * 4,
          );
        }
      }
      // Upstream's canvas goldens pass through Cairo's 8-bit premultiplied
      // surface. Account for that deterministic quantisation, not a tolerance.
      for (var p = 0; p < actual.length; p += 4) {
        final alpha = actual[p + 3];
        for (var channel = 0; channel < 3; channel++) {
          actual[p + channel] = alpha == 0
              ? 0
              : (actual[p + channel] * alpha ~/ 255) * 255 ~/ alpha;
        }
      }
      expect(
        actual,
        File('test/fixtures/pgs/libpgs-$i.rgba').readAsBytesSync(),
      );
    }
  });
  test(
    'seeking backward and before the first caption does not retain later text',
    () {
      final track = decodePgs(bytes);
      final first = track.at(const Duration(milliseconds: 1500));
      expect(track.at(const Duration(milliseconds: 3500)), isNot(same(first)));
      expect(track.at(const Duration(milliseconds: 1500)), same(first));
      expect(track.at(Duration.zero), isNull);
      expect(track.at(const Duration(seconds: 5))!.decode(), isEmpty);
    },
  );
  test('fragmented images, palette updates and cropping preserve authored placement', () {
    final track = decodePgs(_fragmentedTrack());
    final first = track.at(const Duration(milliseconds: 1500))!.decode().single;
    expect((first.x, first.y, first.width, first.height), (3, 4, 2, 1));
    expect(first.rgba, [100, 100, 100, 255, 100, 100, 100, 255]);
    final updated = track
        .at(const Duration(milliseconds: 2500))!
        .decode()
        .single;
    expect(updated.rgba, [200, 200, 200, 255, 200, 200, 200, 255]);
    final crop = track.at(const Duration(milliseconds: 3500))!.decode().single;
    expect((crop.x, crop.y, crop.width, crop.height), (4, 4, 1, 1));
    expect(crop.rgba, [200, 200, 200, 255]);
    expect(track.at(const Duration(seconds: 4))!.decode(), isEmpty);
    expect(
      track.at(const Duration(milliseconds: 1500))!.decode().single.rgba,
      first.rgba,
    );
  });
  test('malformed runs cannot write beyond an object row', () {
    final track = decodePgs(_fragmentedTrack(invalidRun: true));
    expect(
      () => track.at(const Duration(seconds: 1))!.decode(),
      throwsFormatException,
    );
  });
  test('rejects truncated and invalid SUP data', () {
    expect(() => decodePgs(Uint8List.fromList([0, 0])), throwsFormatException);
    expect(
      () => decodePgs(Uint8List.sublistView(bytes, 0, bytes.length - 1)),
      throwsFormatException,
    );
    expect(() => decodePgs(Uint8List(0)), throwsFormatException);
  });
}

Uint8List _sup(int milliseconds, int type, List<int> body) {
  final pts = milliseconds * 90;
  return Uint8List.fromList([
    0x50,
    0x47,
    pts >> 24,
    pts >> 16,
    pts >> 8,
    pts,
    0,
    0,
    0,
    0,
    type,
    body.length >> 8,
    body.length,
    ...body,
  ]);
}

List<int> _pcs({int state = 0, bool clear = false, bool crop = false}) => [
  0,
  10,
  0,
  10,
  0,
  0,
  0,
  state,
  0,
  0,
  clear ? 0 : 1,
  if (!clear) ...[
    0,
    1,
    0,
    crop ? 0x80 : 0,
    0,
    3,
    0,
    4,
    if (crop) ...[0, 1, 0, 0, 0, 1, 0, 1],
  ],
];
Uint8List _fragmentedTrack({bool invalidRun = false}) => Uint8List.fromList([
  ..._sup(1000, 0x16, _pcs(state: 0x80)),
  ..._sup(1000, 0x14, [0, 0, 1, 100, 128, 128, 255]),
  // A two-pixel object split across two ODS segments, total RLE length five.
  ..._sup(1000, 0x15, [
    0,
    1,
    0,
    0x80,
    0,
    0,
    9,
    0,
    2,
    0,
    1,
    0,
    invalidRun ? 0x83 : 0x82,
  ]),
  ..._sup(1000, 0x15, [0, 1, 0, 0x40, 1, 0, 0]),
  ..._sup(1000, 0x80, []),
  ..._sup(2000, 0x16, _pcs()),
  ..._sup(2000, 0x14, [0, 1, 1, 200, 128, 128, 255]),
  ..._sup(2000, 0x80, []),
  ..._sup(3000, 0x16, _pcs(crop: true)),
  ..._sup(3000, 0x80, []),
  ..._sup(4000, 0x16, _pcs(clear: true)),
  ..._sup(4000, 0x80, []),
]);
