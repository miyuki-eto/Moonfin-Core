import 'package:flutter/animation.dart';

/// Motion shared with the Media web interface.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 200);
  static const normal = Duration(milliseconds: 350);
  static const slow = Duration(milliseconds: 450);
  static const screen = Duration(milliseconds: 550);
  static const ease = Cubic(0.22, 1, 0.36, 1);
}
