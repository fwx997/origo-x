import 'package:flutter/material.dart';

import '../../utils/reader_themes.dart';

/// Adjust glyph contrast without changing the paper or the device brightness.
Color readerBodyTextColor(
  ReaderThemePalette palette,
  double brightness,
  bool dimNight,
) {
  final level = dimNight && palette.brightness == Brightness.dark
      ? 0.7
      : brightness.clamp(0.3, 1.0);
  return palette.text.withValues(alpha: palette.text.a * level);
}
