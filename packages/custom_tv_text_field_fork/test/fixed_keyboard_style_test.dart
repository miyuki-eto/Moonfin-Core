import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CustomKeyboard.fixedStyle = null);
  testWidgets(
    'a locked docked keyboard renders without the style key and accepts remote navigation',
    (tester) async {
      CustomKeyboard.fixedStyle = KeyboardStyle.docked;
      final controller = TextEditingController();
      final key = GlobalKey<CustomTVTextFieldState>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomTVTextField(
              key: key,
              controller: controller,
              keyboardStyle: KeyboardStyle.native,
            ),
          ),
        ),
      );
      key.currentState!.openKeyboard();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomKeyboard), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_alt_outlined), findsNothing);
      for (final arrow in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
      ]) {
        await tester.sendKeyEvent(arrow);
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
      key.currentState!.closeKeyboard();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
