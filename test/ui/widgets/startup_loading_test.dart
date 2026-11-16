import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:moonfin/ui/widgets/startup_loading.dart';
import 'package:moonfin/util/tv_ui_scale.dart';

void main() {
  const beamSize = LoadingThrobber.defaultSize;
  for (final size in [
    const Size(960, 540),
    const Size(1145, 644),
    const Size(1920, 1080),
  ]) {
    for (final dpr in [1.0, 2.0]) {
      testWidgets(
        'startup throbber keeps its screen size at $size, DPR $dpr',
        (tester) async {
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            const MaterialApp(home: TvUiScale(child: StartupLoading())),
          );
          final track = find.byKey(const ValueKey('startup-throbber'));
          for (final elapsed in [0, 300, 600]) {
            await tester.pump(Duration(milliseconds: elapsed));
            final rect = tester.getRect(track);
            expect(rect.width, closeTo(beamSize, .01));
            expect(rect.height, closeTo(beamSize / 2, .01));
            expect(rect.center.dx, closeTo(size.width / 2, .01));
            expect(rect.center.dy, closeTo(size.height / 2, .01));
          }
          expect(find.byType(Image), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.textContaining('Moonfin'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('startup respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StartupLoading(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('browser bootstrap matches the shared beam', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('width: ${beamSize.toInt()}px;'));
    expect(html, contains('aspect-ratio: 2;'));
    expect(html, contains('startup-breathe 4s'));
    expect(html, contains('startup-appear 1200ms'));
    expect(html, contains('radial-gradient(ellipse closest-side'));
    expect(html, isNot(contains('Loading Moonfin')));
  });
}
