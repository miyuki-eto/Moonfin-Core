import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/logo_view.dart';
import 'package:moonfin/util/platform_detection.dart';

class _PendingImage extends ImageProvider<_PendingImage> {
  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

void main() {
  testWidgets('a loaded TV logo can change to pending artwork', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    final bytes = await tester.runAsync(() async {
      final image = await createTestImage(width: 4, height: 4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    Future<void> pumpLogo(ImageProvider provider) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: LogoView(
            imageProvider: provider,
            fallback: const Text('Title'),
          ),
        ),
      ),
    );
    await pumpLogo(MemoryImage(bytes!));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNWidgets(2));
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await pumpLogo(_PendingImage());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending or failed logo keeps its readable title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: LogoView(
            imageProvider: MemoryImage(Uint8List.fromList([1, 2, 3])),
            fallback: const Text('A Film'),
          ),
        ),
      ),
    );
    expect(find.text('A Film'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('A Film'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
