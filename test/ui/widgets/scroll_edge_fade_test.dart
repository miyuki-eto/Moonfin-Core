import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/scroll_edge_fade.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets('$axis edges follow scrolling and resized content', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var extent = 900.0;
      var taps = 0;
      late StateSetter resize;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                resize = setState;
                return SizedBox(
                  width: 300,
                  height: 300,
                  child: ScrollEdgeFade(
                    axis: axis,
                    child: SingleChildScrollView(
                      controller: controller,
                      scrollDirection: axis,
                      child: SizedBox(
                        width: axis == Axis.horizontal ? extent : 300,
                        height: axis == Axis.vertical ? extent : 300,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: TextButton(
                            onPressed: () => taps++,
                            child: const Text('Tap'),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Offset edges() => tester
          .widget<TweenAnimationBuilder<Offset>>(
            find.descendant(
              of: find.byType(ScrollEdgeFade),
              matching: find.byType(TweenAnimationBuilder<Offset>),
            ),
          )
          .tween
          .end!;

      expect(edges(), const Offset(0, 1));
      await tester.tap(find.text('Tap'));
      expect(taps, 1); // The overlay cannot consume taps at the edge.
      controller.jumpTo(200);
      await tester.pumpAndSettle();
      expect(edges(), const Offset(1, 1));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(edges(), const Offset(1, 0));
      controller.jumpTo(0);
      resize(() => extent = 100);
      await tester.pumpAndSettle();
      expect(edges(), Offset.zero);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a nested horizontal rail does not activate vertical edges', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollEdgeFade(
            child: ListView(
              children: [
                SizedBox(
                  height: 100,
                  child: ListView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    children: const [SizedBox(width: 2000)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(200);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TweenAnimationBuilder<Offset>>(
            find.byType(TweenAnimationBuilder<Offset>),
          )
          .tween
          .end,
      Offset.zero,
    );
  });

  testWidgets('edges reveal the backdrop instead of painting it black', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 300,
              height: 100,
              child: ColoredBox(
                color: const Color(0xFF0000FF),
                child: ScrollEdgeFade(
                  axis: Axis.horizontal,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [
                      SizedBox(
                        width: 900,
                        child: ColoredBox(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bytes = (await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes;
    }))!;
    final edge = (50 * 300 + 299) * 4;
    expect(bytes.getUint8(edge), lessThan(20));
    expect(bytes.getUint8(edge + 1), lessThan(20));
    expect(
      bytes.getUint8(edge + 2),
      255,
      reason: 'the blue backdrop stays blue through the transparent edge',
    );
    final middle = (50 * 300 + 150) * 4;
    expect(bytes.getUint8(middle), 255);
  });
}
