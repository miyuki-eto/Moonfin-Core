import 'package:web/web.dart' as web;

/// A removed semantics node blurs to the body while the document keeps focus.
/// Browser chrome, another tab, and embedded inputs must retain their focus.
bool get browserViewRetainsFocus =>
    web.document.hasFocus() && web.document.activeElement == web.document.body;
