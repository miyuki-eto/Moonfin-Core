import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/util/focus/input_mode_tracker.dart';
import 'package:moonfin_design/moonfin_design.dart';

void main() {
  testWidgets('a parked pointer cannot highlight a second remote button', (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(MaterialApp(home: InputModeTracker(child: Scaffold(
      body: Row(children: [
        Tv26Button(label: 'First', focusNode: first, autofocus: true,
          onPressed: () {}, onRight: second.requestFocus),
        Tv26Button(label: 'Second', focusNode: second, onPressed: () {}),
      ]),
    ))));
    await tester.pumpAndSettle();
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(find.text('First')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    Color? fill(String label) => (tester.widget<AnimatedContainer>(
      find.descendant(of: find.byWidgetPredicate((w) => w is Tv26Button && w.label == label),
        matching: find.byType(AnimatedContainer)),
    ).decoration as BoxDecoration).color;
    expect(fill('First'), isNot(Tv26Style.foreground));
    expect(fill('Second'), Tv26Style.foreground);
    await pointer.removePointer();
  });
}
