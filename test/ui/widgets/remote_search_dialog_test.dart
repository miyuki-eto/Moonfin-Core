import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/remote_control_dialog.dart';

void main() {
  testWidgets('remote control cannot open in the video-only app', (
    tester,
  ) async {
    // No client is registered: opening this must not start session discovery.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRemoteControlDialog(context),
              child: const Text('Open remote'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open remote'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Open remote'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
