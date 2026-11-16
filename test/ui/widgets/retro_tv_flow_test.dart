import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/playback/retro_tv.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_browser.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_dial.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:server_core/server_core.dart';

class _Channel extends Fake implements RetroChannel {
  _Channel(this.station, DateTime now) {
    this.now = RetroProgram(
      AggregatedItem(
        id: station.name,
        serverId: 'server',
        rawData: {
          'Name': 'Programme ${station.label}',
          'Type': 'Movie',
          'RunTimeTicks': const Duration(minutes: 90).inMicroseconds * 10,
        },
      ),
      now.subtract(const Duration(minutes: 30)),
    );
    next = RetroProgram(
      AggregatedItem(
        id: '${station.name}-next',
        serverId: 'server',
        rawData: {
          'Name': 'Next ${station.label}',
          'Type': 'Movie',
          'RunTimeTicks': const Duration(minutes: 90).inMicroseconds * 10,
        },
      ),
      this.now.endsAt,
    );
  }
  @override
  final RetroStation station;
  @override
  int get number => station.index + 1;
  @override
  late final RetroProgram now;
  @override
  late final RetroProgram next;
}

class _Session extends Fake implements RetroTvSession {
  _Session(this.channels);
  @override
  final List<RetroChannel> channels;
  @override
  RetroChannel get channel => channels.first;
  @override
  RetroChannel? get previousChannel => null;
  @override
  RetroProgram get program => channel.now;
  @override
  RetroProgram get nextProgram => channel.next;
  @override
  bool busy = false;
  @override
  String? get error => null;
  @override
  Uint8List? get transitionFrame => null;
}

class _Client extends Fake implements MediaServerClient {}

void main() {
  late List<RetroChannel> channels;
  setUp(() {
    final now = DateTime.timestamp();
    channels = [
      for (var i = 0; i < 29; i++)
        _Channel(
          RetroStation(
            'test-$i',
            i == 28 ? 'Prime Time' : 'Channel ${i + 1}',
            i,
          ),
          now,
        ),
    ];
  });

  Future<void> mountBrowser(
    WidgetTester tester,
    List<RetroChannel> tuned, {
    double width = 1152,
    RetroChannel? playing,
    VoidCallback? onDismiss,
    VoidCallback? onExit,
  }) async {
    tester.view.physicalSize = Size(width, 648);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(48),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: RetroTvChannelBrowser(
                channels: channels,
                playing: playing ?? channels.first,
                onTune: tuned.add,
                onDismiss: onDismiss ?? () {},
                onExit: onExit ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'vertical browsing wraps without tuning until Enter or the delay',
    (tester) async {
      final tuned = <RetroChannel>[];
      final semantics = tester.ensureSemantics();
      await mountBrowser(tester, tuned);
      await tester.pump(const Duration(seconds: 10));
      expect(tuned, isEmpty);
      await move(tester, LogicalKeyboardKey.arrowUp);
      expect(find.text('Programme Prime Time'), findsOneWidget);
      expect(find.text('Switching in 4s'), findsOneWidget);
      expect(tuned, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Next '), findsNothing);
      expect(find.textContaining('90 min'), findsWidgets);
      final focused = find.byWidgetPredicate(
        (widget) => widget is Tv26Button && widget.focusNode!.hasFocus,
      );
      expect(tester.getSemantics(focused).label, contains('CH 29'));
      final rect = tester.getRect(focused);
      expect(rect.top, greaterThanOrEqualTo(48));
      expect(rect.bottom, lessThanOrEqualTo(648 - 48));
      await move(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text('Watching this channel'), findsOneWidget);
      await move(tester, LogicalKeyboardKey.arrowDown);
      expect(tuned, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tuned, [channels[1]]);
      await tester.pump(const Duration(seconds: 5));
      expect(tuned, [channels[1]]);
      semantics.dispose();
    },
  );

  testWidgets(
    'moving the highlight restarts the full dwell and tunes only once',
    (tester) async {
      final tuned = <RetroChannel>[];
      await mountBrowser(tester, tuned);
      await move(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 2300));
      await move(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(tuned, isEmpty);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tuned, [channels[2]]);
      await tester.pump(const Duration(seconds: 5));
      expect(tuned, [channels[2]]);
    },
  );

  testWidgets('Back just before the dwell expires cancels the pending switch', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    var dismissed = 0;
    await mountBrowser(tester, tuned, onDismiss: () => dismissed++);
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 3750));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 5));
    expect(dismissed, 1);
    expect(tuned, isEmpty);
  });

  testWidgets('Left exits to Media once and cancels pending auto-tuning', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    var exited = 0;
    var dismissed = 0;
    await mountBrowser(
      tester,
      tuned,
      onExit: () => exited++,
      onDismiss: () => dismissed++,
    );
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 3750));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 5));
    expect(exited, 1);
    expect(dismissed, 0);
    expect(tuned, isEmpty);
  });

  testWidgets(
    'reopening the guide centres the playing channel, not a saved offset',
    (tester) async {
      final tuned = <RetroChannel>[];
      final bucket = PageStorageBucket();
      var open = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return open
                      ? RetroTvChannelBrowser(
                          key: const PageStorageKey('guide'),
                          channels: channels,
                          playing: channels[24],
                          onTune: tuned.add,
                          onDismiss: () {},
                          onExit: () {},
                        )
                      : const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await move(tester, LogicalKeyboardKey.arrowDown);
      }
      update(() => open = false);
      await tester.pumpAndSettle();
      update(() => open = true);
      await tester.pumpAndSettle();
      final focused = find.byWidgetPredicate(
        (widget) => widget is Tv26Button && widget.focusNode!.hasFocus,
      );
      expect(focused, findsOneWidget);
      expect(tester.widget<Tv26Button>(focused).label, contains('CH 25'));
      expect(
        tester.getCenter(focused).dy,
        closeTo(tester.getCenter(find.byType(ListWheelScrollView)).dy, .1),
      );
      expect(tuned, isEmpty);
    },
  );

  testWidgets('Right closes the guide without exiting or tuning', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    var exited = 0;
    var dismissed = 0;
    await mountBrowser(
      tester,
      tuned,
      onExit: () => exited++,
      onDismiss: () => dismissed++,
    );
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 5));
    expect(exited, 0);
    expect(dismissed, 1);
    expect(tuned, isEmpty);
  });

  testWidgets('returning to the playing channel cancels auto-selection', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    await mountBrowser(tester, tuned);
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await move(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Watching this channel'), findsOneWidget);
    expect(tuned, isEmpty);
  });

  testWidgets(
    'closing or backgrounding the guide cannot leave a delayed tune',
    (tester) async {
      final tuned = <RetroChannel>[];
      await mountBrowser(tester, tuned);
      await move(tester, LogicalKeyboardKey.arrowDown);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 5));
      expect(tuned, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await move(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tuned, isEmpty);
    },
  );

  testWidgets('losing focus cancels a pending dwell', (tester) async {
    final tuned = <RetroChannel>[];
    await mountBrowser(tester, tuned);
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(tuned, isEmpty);
  });

  testWidgets('manual scrolling cancels the selection countdown', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    await mountBrowser(tester, tuned);
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -200));
    await tester.pump(const Duration(seconds: 5));
    expect(tuned, isEmpty);
  });

  testWidgets('the wheel stays centred and wraps by one smooth row', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    await mountBrowser(tester, tuned);
    final wheel = find.byType(ListWheelScrollView);
    final controller = tester.widget<ListWheelScrollView>(wheel).controller!;
    final focused = find.byWidgetPredicate(
      (widget) => widget is Tv26Button && widget.focusNode!.hasFocus,
    );
    final center = tester.getCenter(wheel).dy;
    expect(tester.getCenter(focused).dy, closeTo(center, .1));
    final start = controller.offset;
    final extent = tester.widget<ListWheelScrollView>(wheel).itemExtent;
    await move(tester, LogicalKeyboardKey.arrowUp);
    // A real animated step, not a jump from the first to the last item.
    expect(controller.offset, lessThan(start));
    expect(controller.offset, greaterThan(start - extent));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.offset, closeTo(start - extent, .1));
    expect(tester.getCenter(focused).dy, closeTo(center, .1));
    expect((tester.widget<Tv26Button>(focused)).label, contains('CH 29'));
    await move(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.offset, closeTo(start, .1));
    expect(tester.getCenter(focused).dy, closeTo(center, .1));
    expect((tester.widget<Tv26Button>(focused)).label, contains('CH 01'));
    expect(tuned, isEmpty);
  });

  testWidgets('rapid remote browsing keeps focus through a full loop', (
    tester,
  ) async {
    final tuned = <RetroChannel>[];
    await mountBrowser(tester, tuned);
    for (var i = 0; i < channels.length + 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
    }
    await tester.pump(const Duration(milliseconds: 400));
    final focused = find.byWidgetPredicate(
      (widget) => widget is Tv26Button && widget.focusNode!.hasFocus,
    );
    expect(focused, findsOneWidget);
    expect(tester.widget<Tv26Button>(focused).label, contains('CH 04'));
    expect(
      tester.getCenter(focused).dy,
      closeTo(tester.getCenter(find.byType(ListWheelScrollView)).dy, .1),
    );
    expect(tuned, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(tuned, [channels[3]]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening on a distant playing channel fits a narrow viewport and keeps focus visible',
    (tester) async {
      final tuned = <RetroChannel>[];
      await mountBrowser(tester, tuned, width: 720, playing: channels[20]);
      final focused = find.byWidgetPredicate(
        (widget) => widget is Tv26Button && widget.focusNode!.hasFocus,
      );
      expect(focused, findsOneWidget);
      final rect = tester.getRect(focused);
      expect(rect.top, greaterThanOrEqualTo(48));
      expect(rect.bottom, lessThanOrEqualTo(648 - 48));
      expect(rect.left, greaterThanOrEqualTo(48));
      expect(rect.right, lessThanOrEqualTo(720 - 48));
      expect(tester.takeException(), isNull);
      expect(tuned, isEmpty);
    },
  );

  testWidgets(
    'channel banners never claim focus and only passive banners time out',
    (tester) async {
      final session = _Session(channels);
      final videoFocus = FocusNode();
      addTearDown(videoFocus.dispose);
      var dismissed = 0;
      Future<void> mount(RetroTvPanel panel) async {
        tester.view.physicalSize = const Size(1152, 648);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Focus(
                focusNode: videoFocus,
                autofocus: true,
                child: RetroTvOverlay(
                  session: session,
                  failed: false,
                  panel: panel,
                  client: _Client(),
                  onTune: (_) {},
                  onAction: (_) {},
                  onDismiss: () => dismissed++,
                  onCloseActions: () {},
                  onExit: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
      }

      addTearDown(tester.view.reset);
      await mount(RetroTvPanel.banner);
      expect(find.byType(Tv26Button), findsNothing);
      final identity = tester.getRect(find.byType(RetroTvChannelBanner));
      final schedule = tester.getRect(find.byType(RetroTvBanner));
      expect(identity.top, 0);
      expect(identity.width, 1152);
      expect(schedule.bottom, 648);
      expect(schedule.width, 1152);
      expect(identity.bottom, lessThan(schedule.top));
      expect(videoFocus.hasPrimaryFocus, isTrue);
      expect(find.text('60 min left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(dismissed, 1);
      await mount(RetroTvPanel.actions);
      await tester.pump(const Duration(seconds: 10));
      expect(dismissed, 1);
      expect(find.text('View Details'), findsOneWidget);
      expect(
        tester
            .widget<Tv26Button>(find.byType(Tv26Button).first)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await mount(RetroTvPanel.hidden);
      expect(find.byType(Tv26Button), findsNothing);
      expect(find.byType(RetroTvChannelBanner), findsNothing);
      expect(find.byType(RetroTvBanner), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
