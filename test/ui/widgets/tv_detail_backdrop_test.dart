import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/tv/tv_detail_backdrop.dart';

void main() {
  testWidgets(
    'scrolling reveals the bottom of page-anchored artwork then black',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final boundary = GlobalKey();
      const artwork = ValueKey('artwork');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 400,
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TvDetailBackdrop(
                      scrollController: controller,
                      heroExtent: 200,
                      child: const Column(
                        key: artwork,
                        children: [
                          SizedBox(
                            height: 100,
                            width: double.infinity,
                            child: ColoredBox(color: Color(0xFF0000FF)),
                          ),
                          Expanded(
                            child: ColoredBox(
                              color: Color(0xFF00FF00),
                              child: SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListView(
                      controller: controller,
                      padding: EdgeInsets.zero,
                      children: const [SizedBox(height: 1000)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<int> channelAt(int y, [int channel = 2]) async {
        final bytes = (await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes;
        }))!;
        return bytes.getUint8((y * 400 + 200) * 4 + channel);
      }

      final originalBounds = tester.getRect(find.byKey(artwork));
      expect(await channelAt(30), 255);
      expect(await channelAt(190, 1), inExclusiveRange(0, 80));
      expect(
        await channelAt(240, 1),
        0,
        reason: 'Below the hero is solid black',
      );
      controller.jumpTo(100);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(artwork)),
        originalBounds.shift(const Offset(0, -100)),
      );
      expect(await channelAt(30), 0, reason: 'The blue top has scrolled away');
      expect(
        await channelAt(30, 1),
        inExclusiveRange(0, 100),
        reason: 'The green picture is visible but shaded in the text band',
      );
      expect(await channelAt(130, 1), 0);
      controller.jumpTo(240);
      await tester.pumpAndSettle();
      expect(await channelAt(30, 1), 0);
      expect(await channelAt(240, 1), 0);
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        await channelAt(30),
        255,
        reason: 'Returning to the hero restores artwork',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
