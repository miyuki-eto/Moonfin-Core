import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/background/auto_download_background_main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a stale scheduled download worker finishes permanently without restoring a session', () async {
    const channel = MethodChannel('org.moonfin.androidtv/auto_download');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await autoDownloadBackgroundMain();
    expect(calls.map((call) => call.method), ['backgroundComplete']);
    expect(calls.single.arguments, {'ok': true, 'permanent': true});
  });
}
