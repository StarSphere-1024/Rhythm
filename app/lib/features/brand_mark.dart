import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// The Rhythm mark, rendered with the active theme's paired container roles.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: '节律',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _BrandMarkPainter(
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({required this.background, required this.foreground});

  final Color background;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 108;
    final backgroundPaint = Paint()..color = background;
    final foregroundPaint = Paint()..color = foreground;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(24 * scale)),
      backgroundPaint,
    );
    for (final rect in const [
      Rect.fromLTRB(24, 34, 38, 56),
      Rect.fromLTRB(47, 27, 61, 56),
      Rect.fromLTRB(70, 20, 84, 56),
    ]) {
      final scaled = Rect.fromLTRB(
        rect.left * scale,
        rect.top * scale,
        rect.right * scale,
        rect.bottom * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, Radius.circular(7 * scale)),
        foregroundPaint,
      );
    }
    canvas.drawLine(
      Offset(32 * scale, 69 * scale),
      Offset(45 * scale, 82 * scale),
      foregroundPaint
        ..strokeWidth = 8 * scale
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(45 * scale, 82 * scale),
      Offset(76 * scale, 61 * scale),
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground;
}

@Preview(name: 'Brand mark · light', group: 'Rhythm')
Widget brandMarkLightPreview() => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff208d78)),
  ),
  home: const Scaffold(body: Center(child: BrandMark(size: 120))),
);

@Preview(
  name: 'Brand mark · dark',
  group: 'Rhythm',
  brightness: Brightness.dark,
)
Widget brandMarkDarkPreview() => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff208d78),
      brightness: Brightness.dark,
    ),
  ),
  home: const Scaffold(body: Center(child: BrandMark(size: 120))),
);
