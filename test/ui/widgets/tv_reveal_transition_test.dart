import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/tv/tv_reveal_transition.dart';
import 'package:moonfin/ui/widgets/fullscreen_backdrop_switcher.dart';
import 'package:moonfin_design/moonfin_design.dart';

void main() {
  testWidgets(
    'native video stays unfiltered and covered until ready, then fades in',
    (tester) async {
      Widget surface(bool ready) => MaterialApp(
        home: TvContentReveal(
          nativeSurface: true,
          ready: ready,
          child: const Text('hardware video plane'),
        ),
      );
      await tester.pumpWidget(surface(false));
      double coverOpacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(TvContentReveal),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(coverOpacity(), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(coverOpacity(), 1);
      expect(find.byType(ImageFiltered), findsNothing);
      await tester.pumpWidget(surface(true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(coverOpacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(coverOpacity(), 0);
      expect(find.text('hardware video plane'), findsOneWidget);
    },
  );

  testWidgets(
    'native reveal honors reduced motion when content becomes ready',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: TvContentReveal(nativeSurface: true, child: Text('video')),
          ),
        ),
      );
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(TvContentReveal),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        0,
      );
    },
  );

  testWidgets('artwork fades, sharpens and settles at its original size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullscreenBackdropSwitcher(
          imageUrl: 'art',
          animateInitialImage: true,
          softenTransition: true,
          duration: AppMotion.slow,
          imageBuilder: _art,
        ),
      ),
    );
    await tester.pump();
    final reveal = find.byType(TvRevealTransition);
    Animation<double> animation() =>
        tester.widget<TvRevealTransition>(reveal).animation;
    expect(animation().value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(animation().value, inExclusiveRange(0, 1));
    final filter = tester.widget<ImageFiltered>(
      find.descendant(of: reveal, matching: find.byType(ImageFiltered)),
    );
    expect(filter.enabled, isTrue);
    final transform = tester.widget<Transform>(
      find.descendant(of: reveal, matching: find.byType(Transform)),
    );
    expect(transform.transform.storage[0], inExclusiveRange(1, 1.012));
    await tester.pumpAndSettle();
    expect(find.byType(TvRevealTransition), findsNothing);
    expect(find.text('art'), findsOneWidget);
  });

  testWidgets('reduced motion shows content sharp at full size immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: TvRevealTransition(
            animation: AlwaysStoppedAnimation(.3),
            child: Text('Film'),
          ),
        ),
      ),
    );
    final reveal = find.byType(TvRevealTransition);
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(of: reveal, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value,
      1,
    );
    expect(
      tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
      isFalse,
    );
    expect(
      tester.widget<Transform>(find.byType(Transform)).transform.storage[0],
      1,
    );
  });
}

Widget _art(String url) => Text(url);
