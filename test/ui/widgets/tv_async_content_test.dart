import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/tv/tv_async_content.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';

void main() {
  testWidgets('a delayed response does not steal focus from an open sidebar', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    final sidebar = FocusNode();
    final content = FocusNode();
    addTearDown(() {
      ready.dispose();
      sidebar.dispose();
      content.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Tv26Button(label: 'Sidebar', focusNode: sidebar, onPressed: () {}),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: ready,
                builder: (_, value, _) => TvAsyncContent(
                  ready: value,
                  initialFocusNode: content,
                  child: Center(
                    child: Tv26Button(
                      label: 'Content',
                      focusNode: content,
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    sidebar.requestFocus();
    await tester.pump();
    ready.value = true;
    await tester.pumpAndSettle();
    expect(sidebar.hasPrimaryFocus, isTrue);
    expect(content.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  for (final preferred in [false, true]) {
    testWidgets(
      'delayed ready content focuses a control (preferred=$preferred), then preserves it on refresh',
      (tester) async {
        final ready = ValueNotifier(false);
        final home = FocusNode();
        final sort = FocusNode();
        addTearDown(() {
          ready.dispose();
          home.dispose();
          sort.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: ready,
              builder: (_, value, _) => TvAsyncContent(
                ready: value,
                initialFocusNode: preferred ? sort : null,
                child: Scaffold(
                  body: Focus(
                    child: Row(
                      children: [
                        Tv26Button(
                          label: 'Home',
                          focusNode: home,
                          onPressed: () {},
                        ),
                        Tv26Button(
                          label: 'Sort',
                          focusNode: sort,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(home.hasFocus || sort.hasFocus, isFalse);
        ready.value = true;
        await tester.pumpAndSettle();
        expect((preferred ? sort : home).hasPrimaryFocus, isTrue);
        sort.requestFocus();
        await tester.pump();
        ready.value = false;
        await tester.pump();
        ready.value = true;
        await tester.pumpAndSettle();
        expect(sort.hasPrimaryFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
