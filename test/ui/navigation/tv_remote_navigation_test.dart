import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/tv/tv_remote_navigation.dart';
import 'package:moonfin/util/platform_detection.dart';

// Flutter's web defaults scroll with arrows. Reproduce that host behavior;
// the native test platform's default focus shortcuts would hide this bug.
Map<ShortcutActivator, Intent> browserShortcuts() => {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.arrowUp): const ScrollIntent(
    direction: AxisDirection.up,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowDown): const ScrollIntent(
    direction: AxisDirection.down,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowLeft): const ScrollIntent(
    direction: AxisDirection.left,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowRight): const ScrollIntent(
    direction: AxisDirection.right,
  ),
};

void main() {
  tearDown(
    () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
  );

  testWidgets(
    'TV overrides browser scrolling with focus traversal and retains activation and Tab',
    (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
      final nodes = List.generate(4, (_) => FocusNode());
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      var selected = -1;
      Widget button(int index) => SizedBox(
        width: 150,
        height: 60,
        child: TextButton(
          autofocus: index == 0,
          focusNode: nodes[index],
          onPressed: () => selected = index,
          child: Text('$index'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          shortcuts: browserShortcuts(),
          home: TvRemoteNavigation(
            child: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [button(0), button(1)],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [button(2), button(3)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final (key, index) in [
        (LogicalKeyboardKey.arrowDown, 2),
        (LogicalKeyboardKey.arrowRight, 3),
        (LogicalKeyboardKey.arrowUp, 1),
        (LogicalKeyboardKey.arrowLeft, 0),
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(nodes[index].hasPrimaryFocus, isTrue);
      }
      // Match Flutter View's unfocused event after a web semantics node is
      // removed during navigation: the root parks focus, retaining the view's
      // remembered route beneath it.
      FocusManager.instance.rootScope.requestScopeFocus();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        FocusManager.instance.rootScope,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(nodes[2].hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(nodes[0].hasPrimaryFocus, isTrue);
      FocusManager.instance.rootScope.requestScopeFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 0, reason: 'Select also recovers and activates once');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(nodes[1].hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-TV retains browser scrolling', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        shortcuts: browserShortcuts(),
        home: TvRemoteNavigation(
          child: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(
                    height: 80,
                    child: TextButton(
                      autofocus: i == 0,
                      onPressed: () {},
                      child: Text('$i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final original = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(FocusManager.instance.primaryFocus, same(original));
  });

  testWidgets('text editing retains its own arrow keys', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    final controller = TextEditingController(text: 'Film');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        shortcuts: browserShortcuts(),
        home: TvRemoteNavigation(
          child: Scaffold(
            body: TextField(autofocus: true, controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 1);
    final field = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.baseOffset, 2);
    expect(FocusManager.instance.primaryFocus, same(field));
  });
}
