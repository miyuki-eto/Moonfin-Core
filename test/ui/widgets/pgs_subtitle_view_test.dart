import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/pgs/pgs_decoder.dart';
import 'package:moonfin/ui/widgets/pgs_subtitle_view.dart';

void main() {
  testWidgets(
    'native bitmap view paints, clears on backward seek and releases late frames',
    (tester) async {
      final track = decodePgs(
        File('test/fixtures/pgs/libpgs.sup').readAsBytesSync(),
      );
      final boundary = GlobalKey();
      final errors = <Object>[];
      Widget scene(Duration at) => Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: const Color(0xff000000),
            child: PgsSubtitleView(
              track: track,
              position: at,
              onError: errors.add,
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene(const Duration(milliseconds: 1500)));
      for (
        var i = 0;
        i < 100 && find.byType(RawImage).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsOneWidget);
      expect(errors, isEmpty);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = File('build/verification/pgs-native-widget.png');
          await out.parent.create(recursive: true);
          await out.writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(scene(Duration.zero));
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(scene(const Duration(milliseconds: 3500)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
