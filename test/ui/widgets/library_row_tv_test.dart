import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/library_row.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin_design/moonfin_design.dart';

void main() {
  testWidgets('TV search rows share gutters, spacing and viewport bounds', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: Padding(
                padding: Tv26Style.railPadding,
                child: LibraryRow(
                  title: 'Movies',
                  rowHeight: 100,
                  scrollController: controller,
                  children: [
                    for (var index = 0; index < 8; index++)
                      SizedBox(
                        key: ValueKey(index),
                        width: 100,
                        child: const ColoredBox(color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byKey(const ValueKey(0)));
    final next = tester.getRect(find.byKey(const ValueKey(1)));
    expect(next.left - first.right, Tv26Style.railItemGap);
    final viewport = tester.getRect(find.byType(ShaderMask));
    expect(
      viewport.width,
      400 + 2 * (Tv26Style.focusOutset + Tv26Style.railFadeDistance),
    );
    controller.jumpTo(124);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey(1))).left, first.left);
    expect(tester.takeException(), isNull);
  });
}
