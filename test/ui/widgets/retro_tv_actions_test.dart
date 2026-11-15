import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/playback/retro_tv.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_dial.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';

RetroProgram programme(String name, {String? series}) => RetroProgram(
  AggregatedItem(
    id: name,
    serverId: 'server',
    rawData: {
      'Name': name,
      'Type': series == null ? 'Movie' : 'Episode',
      if (series != null) ...{
        'SeriesName': series,
        'ParentIndexNumber': 1,
        'IndexNumber': 2,
      },
      'RunTimeTicks': const Duration(minutes: 90).inMicroseconds * 10,
    },
  ),
  DateTime.utc(2026),
);

void main() {
  Future<void> mount(
    WidgetTester tester, {
    RetroProgram? program,
    Widget? details,
    double width = 1152,
    bool enabled = true,
    bool previous = true,
    required ValueChanged<RetroTvAction> onAction,
    VoidCallback? onDismiss,
  }) async {
    tester.view.physicalSize = Size(width, 648);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: RetroTvActionMenu(
              program: program ?? programme('Movie'),
              details: details,
              actionsEnabled: enabled,
              previousAvailable: previous,
              onAction: onAction,
              onDismiss: onDismiss ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'four actions form a vertical right-side menu with Info focused',
    (tester) async {
      await mount(tester, onAction: (_) {});
      final menu = tester.getRect(find.byType(RetroTvActionMenu));
      expect(menu.right, 1152);
      expect(menu.height, 648);
      final buttons = find.byType(Tv26Button);
      expect(buttons, findsNWidgets(4));
      expect(
        tester.widget<Tv26Button>(buttons.first).focusNode!.hasFocus,
        isTrue,
      );
      expect(find.byType(Dialog), findsNothing);
      for (var i = 1; i < 4; i++) {
        expect(
          tester.getRect(buttons.at(i)).left,
          tester.getRect(buttons.first).left,
        );
        expect(
          tester.getRect(buttons.at(i)).top,
          greaterThan(tester.getRect(buttons.at(i - 1)).bottom),
        );
      }
    },
  );

  testWidgets('Up Down select actions and Left dismisses without activation', (
    tester,
  ) async {
    final selected = <RetroTvAction>[];
    var dismissed = 0;
    await mount(tester, onAction: selected.add, onDismiss: () => dismissed++);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(selected, [
      RetroTvAction.details,
      RetroTvAction.watch,
      RetroTvAction.startOver,
      RetroTvAction.previous,
    ]);
    expect(
      tester
          .widget<Tv26Button>(find.byType(Tv26Button).last)
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      tester
          .widget<Tv26Button>(find.byType(Tv26Button).at(2))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(dismissed, 1);
    expect(selected.length, 4);
  });

  testWidgets(
    'unavailable playback actions cannot activate while Info stays usable',
    (tester) async {
      final selected = <RetroTvAction>[];
      await mount(
        tester,
        enabled: false,
        previous: false,
        onAction: selected.add,
      );
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      expect(selected, [RetroTvAction.details]);
    },
  );

  testWidgets(
    'details expand left while action geometry and focus stay fixed',
    (tester) async {
      final current = programme('Movie');
      await mount(tester, program: current, onAction: (_) {});
      final bounds = [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byType(Tv26Button).at(i)),
      ];
      await mount(
        tester,
        program: current,
        details: const Text('Synopsis'),
        onAction: (_) {},
      );
      expect(find.text('Hide Details'), findsOneWidget);
      expect(
        tester
            .widget<Tv26Button>(find.byType(Tv26Button).first)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      for (var i = 0; i < 4; i++) {
        expect(tester.getRect(find.byType(Tv26Button).at(i)), bounds[i]);
      }
      await mount(
        tester,
        program: current,
        details: const Text('Synopsis'),
        width: 720,
        onAction: (_) {},
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(RetroTvActionMenu)).right, 720);
    },
  );

  testWidgets('long movie and series titles keep action positions steady', (
    tester,
  ) async {
    double? firstTop;
    for (final current in [
      programme('Heat'),
      programme(
        'A Very Long Movie Name That Wraps Across Two Lines In The Menu',
      ),
      programme(
        'The Gang Gets Racist',
        series: "It's Always Sunny in Philadelphia",
      ),
    ]) {
      await mount(tester, program: current, onAction: (_) {});
      final top = tester.getTopLeft(find.byType(Tv26Button).first).dy;
      firstTop ??= top;
      expect(top, firstTop);
      expect(tester.takeException(), isNull);
    }
  });
}
