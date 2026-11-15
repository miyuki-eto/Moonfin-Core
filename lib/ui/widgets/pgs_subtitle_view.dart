import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../playback/pgs/pgs_decoder.dart';

Future<ui.Image> _image(PgsBitmap bitmap) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bitmap.rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: bitmap.width,
    height: bitmap.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  try {
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

List<PgsBitmap> _decode(PgsFrame frame) {
  final bitmaps = frame.decode();
  // Flutter's raw RGBA input is premultiplied; libpgs' palette is straight RGBA.
  // Do this alongside RLE decoding in the worker, never on the TV's UI thread.
  for (final bitmap in bitmaps) {
    final pixels = bitmap.rgba;
    for (var i = 0; i < pixels.length; i += 4) {
      final a = pixels[i + 3];
      for (var c = 0; c < 3; c++) {
        pixels[i + c] = (pixels[i + c] * a + 127) ~/ 255;
      }
    }
  }
  return bitmaps;
}

/// Native equivalent of Moonfin's PGS canvas. Authored placement, colours and
/// clear events are retained; typography controls apply to text subtitles only.
class PgsSubtitleView extends StatefulWidget {
  const PgsSubtitleView({
    super.key,
    required this.track,
    required this.position,
    required this.onError,
    this.fit = BoxFit.contain,
  });
  final PgsTimeline track;
  final Duration position;
  final BoxFit fit;
  final ValueChanged<Object> onError;
  @override
  State<PgsSubtitleView> createState() => _PgsSubtitleViewState();
}

class _PgsSubtitleViewState extends State<PgsSubtitleView> {
  PgsFrame? _frame;
  List<({PgsBitmap bitmap, ui.Image image})> _images = [];
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(PgsSubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _releaseImages() {
    for (final entry in _images) {
      entry.image.dispose();
    }
    _images = [];
  }

  void _update() {
    final frame = widget.track.at(widget.position);
    if (identical(frame, _frame)) return;
    _frame = frame;
    final generation = ++_generation;
    _releaseImages();
    if (frame != null) _load(frame, generation);
  }

  Future<void> _load(PgsFrame frame, int generation) async {
    final loaded = <({PgsBitmap bitmap, ui.Image image})>[];
    try {
      final bitmaps = await compute(_decode, frame);
      if (!mounted || generation != _generation) return;
      for (final bitmap in bitmaps) {
        final image = await _image(bitmap);
        loaded.add((bitmap: bitmap, image: image));
      }
      if (!mounted || generation != _generation) {
        for (final entry in loaded) {
          entry.image.dispose();
        }
        return;
      }
      setState(() => _images = loaded);
    } catch (error) {
      for (final entry in loaded) {
        entry.image.dispose();
      }
      if (mounted && generation == _generation) widget.onError(error);
    }
  }

  @override
  void dispose() {
    ++_generation;
    _releaseImages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null || _images.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: FittedBox(
          fit: widget.fit,
          child: SizedBox(
            width: frame.width.toDouble(),
            height: frame.height.toDouble(),
            child: Stack(
              children: [
                for (final entry in _images)
                  Positioned(
                    left: entry.bitmap.x.toDouble(),
                    top: entry.bitmap.y.toDouble(),
                    width: entry.bitmap.width.toDouble(),
                    height: entry.bitmap.height.toDouble(),
                    child: RawImage(
                      image: entry.image,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
