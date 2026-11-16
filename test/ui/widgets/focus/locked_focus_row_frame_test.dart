import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';
import 'package:moonfin/ui/widgets/media_card.dart';
import 'package:moonfin/util/platform_detection.dart';

void main() {
  for (final insetSection in [false, true]) {
    testWidgets('rail fades stay consistent for inset section=$insetSection', (
      tester,
    ) async {
      final boundary = GlobalKey();
      final row = GlobalKey<LockedFocusRowState<int>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 400,
                height: 150,
                child: ColoredBox(
                  color: const Color(0xFF0000FF),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: insetSection ? 48 : 0,
                    ),
                    child: LockedFocusRow<int>(
                      key: row,
                      items: const [0, 1, 2, 3, 4, 5],
                      hubKey: 'leading-fade-pixels',
                      height: 150,
                      itemExtent: 120,
                      paintOutset: 6,
                      padding: insetSection
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(horizontal: 48),
                      viewportInsets: insetSection
                          ? const EdgeInsets.symmetric(horizontal: 48)
                          : EdgeInsets.zero,
                      clipBehavior: Clip.none,
                      onTap: (_, _) {},
                      itemBuilder: (_, _, _, _) => const Padding(
                        padding: EdgeInsets.only(right: 20),
                        child: SizedBox(
                          width: 100,
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      row.currentState!.requestFocusAt(1);
      await tester.pumpAndSettle();
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
      final edge = (50 * 400 + 1) * 4;
      expect(bytes.getUint8(edge), lessThan(20));
      expect(
        bytes.getUint8(edge + 2),
        255,
        reason: 'The leading fade reveals the blue backdrop',
      );
      final selected = (50 * 400 + 55) * 4;
      expect(
        bytes.getUint8(selected),
        255,
        reason: 'The selected card stays fully opaque',
      );
      final beforeTrailingFade = (50 * 400 + 350) * 4;
      expect(
        bytes.getUint8(beforeTrailingFade),
        255,
        reason: 'The trailing fade must not spread beyond the shared gutter',
      );
      final trailingFade = (50 * 400 + 385) * 4;
      expect(bytes.getUint8(trailingFade), lessThan(200));
      expect(bytes.getUint8(trailingFade + 2), 255);
    });
  }

  testWidgets(
    'TV rail contains all four focus edges without moving artwork or losing arrow selection',
    (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
      addTearDown(
        () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
      );
      int? selected;
      final key = GlobalKey<LockedFocusRowState<int>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: LockedFocusRow<int>(
                  key: key,
                  items: const [0, 1, 2, 3, 4, 5, 6, 7],
                  hubKey: 'focus-frame-bounds',
                  height: 150,
                  itemExtent: 120,
                  paintOutset: MediaCard.focusRingOutset,
                  clipBehavior: Clip.none,
                  onTap: (index, _) => selected = index,
                  itemBuilder: (context, item, index, focused) => Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: MediaCard(
                      title: 'Film $item',
                      width: 100,
                      aspectRatio: 2 / 3,
                      showLabel: false,
                      externalIsFocused: focused,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      key.currentState!.requestFocusAt(0);
      await tester.pumpAndSettle();
      final image = tester.getRect(
        find
            .descendant(
              of: find.byType(MediaCard).first,
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      final viewport = tester.getRect(find.byType(ShaderMask));
      final frame = image.inflate(5);
      expect(viewport.left, lessThanOrEqualTo(frame.left));
      expect(viewport.right, greaterThanOrEqualTo(frame.right));
      expect(viewport.top, lessThanOrEqualTo(frame.top));
      expect(viewport.bottom, greaterThanOrEqualTo(frame.bottom));
      expect(
        image.left,
        closeTo(tester.getRect(find.byType(LockedFocusRow<int>)).left, .01),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final selectedImage = tester.getRect(
        find
            .descendant(
              of: find.byType(MediaCard).at(1),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      // Paint padding must not be mistaken for layout drift and scroll the
      // selected card out through the leading fade.
      expect(selectedImage.left, closeTo(image.left, .01));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(key.currentState!.hasFocusedItem, isTrue);
    },
  );
}
