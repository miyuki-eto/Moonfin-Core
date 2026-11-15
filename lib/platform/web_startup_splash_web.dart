import 'dart:async';

import 'package:web/web.dart' as web;

web.Element? get _splash => web.document.getElementById('moonfin-loader');

bool get webStartupSplashVisible => _splash != null;

void finishWebStartupSplash() {
  final splash = _splash;
  if (splash == null || splash.classList.contains('ready')) return;
  splash.classList.add('ready');
  Timer(const Duration(milliseconds: 220), () => splash.remove());
}
