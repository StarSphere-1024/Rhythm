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

  static final _tile = RRect.fromRectAndRadius(
    const Rect.fromLTWH(15, 15, 70, 70),
    const Radius.circular(19),
  );
  static final _bars = [
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(29, 28, 12, 16),
      const Radius.circular(4),
    ),
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(46, 28, 12, 28),
      const Radius.circular(4),
    ),
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(63, 28, 9, 21),
      const Radius.circular(4),
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    final backgroundPaint = Paint()..color = background;
    final foregroundPaint = Paint()..color = foreground;
    canvas.drawRRect(_tile, backgroundPaint);
    for (final bar in _bars) {
      canvas.drawRRect(bar, foregroundPaint);
    }
    canvas.drawLine(
      const Offset(29, 66),
      const Offset(43, 75),
      foregroundPaint
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      const Offset(43, 75),
      const Offset(70, 51),
      foregroundPaint,
    );
    canvas.restore();
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
