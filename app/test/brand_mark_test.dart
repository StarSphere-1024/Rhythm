import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/features/brand_mark.dart';
import 'package:rhythm/main.dart';

void main() {
  group('rhythmTheme', () {
    const seeds = [Color(0xff208d78), Color(0xff6750a4)];

    test('derives paired semantic colors from each seed in both modes', () {
      for (final brightness in Brightness.values) {
        final themes = [
          for (final seed in seeds) rhythmTheme(brightness, seedColor: seed),
        ];
        final first = themes[0];
        final second = themes[1];

        expect(first.colorScheme.brightness, brightness);
        expect(second.colorScheme.brightness, brightness);
        expect(first.scaffoldBackgroundColor, first.colorScheme.surface);
        expect(second.scaffoldBackgroundColor, second.colorScheme.surface);
        expect(
          first.colorScheme.primaryContainer,
          isNot(second.colorScheme.primaryContainer),
        );
        expect(
          first.colorScheme.onPrimaryContainer,
          isNot(second.colorScheme.onPrimaryContainer),
        );
      }
    });
  });

  testWidgets('brand mark is sized and accessible with each brightness', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: rhythmTheme(brightness),
            home: const Scaffold(body: BrandMark(size: 48)),
          ),
        );

        expect(find.bySemanticsLabel('节律'), findsOneWidget);
        expect(tester.getSize(find.byType(BrandMark)), const Size(48, 48));
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('brand mark pixels follow theme changes without restarting', (
    tester,
  ) async {
    const boundaryKey = Key('brand-mark-boundary');

    Future<int> backgroundPixel() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return bytes!.getUint32((40 * 48 + 24) * 4, Endian.big);
        } finally {
          image.dispose();
        }
      }))!;
    }

    Widget themedMark(Brightness brightness, Color seedColor) => MaterialApp(
      theme: rhythmTheme(brightness, seedColor: seedColor),
      home: const Scaffold(
        body: Center(
          child: RepaintBoundary(key: boundaryKey, child: BrandMark(size: 48)),
        ),
      ),
    );

    await tester.pumpWidget(
      themedMark(Brightness.light, const Color(0xff208d78)),
    );
    await tester.pumpAndSettle();
    final before = await backgroundPixel();
    await tester.pumpWidget(
      themedMark(Brightness.light, const Color(0xff6750a4)),
    );
    await tester.pumpAndSettle();
    final recolored = await backgroundPixel();
    await tester.pumpWidget(
      themedMark(Brightness.dark, const Color(0xff6750a4)),
    );
    await tester.pumpAndSettle();
    final dark = await backgroundPixel();

    expect(before, isNot(recolored));
    expect(recolored, isNot(dark));
  });

  testWidgets('brand mark retains the original padded silhouette', (
    tester,
  ) async {
    const boundaryKey = Key('brand-mark-silhouette');

    for (final brightness in Brightness.values) {
      final theme = rhythmTheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: BrandMark(size: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final bytes = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
        }
      }))!;

      Color pixel(int x, int y) {
        final offset = (y * 100 + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }

      final foreground = theme.colorScheme.onPrimaryContainer;
      final background = theme.colorScheme.primaryContainer;
      for (final point in const [
        Offset(34, 32),
        Offset(51, 32),
        Offset(67, 32),
        Offset(50, 52),
        Offset(70, 40),
        Offset(30, 67),
        Offset(43, 74),
        Offset(60, 60),
      ]) {
        expect(
          pixel(point.dx.toInt(), point.dy.toInt()),
          foreground,
          reason: '$brightness: foreground at $point',
        );
      }
      for (final point in const [
        Offset(34, 48),
        Offset(67, 24),
        Offset(75, 35),
        Offset(42, 81),
        Offset(50, 20),
      ]) {
        expect(
          pixel(point.dx.toInt(), point.dy.toInt()),
          background,
          reason: '$brightness: empty tile at $point',
        );
      }
      for (final point in const [
        Offset(50, 10),
        Offset(10, 50),
        Offset(90, 50),
        Offset(50, 90),
        Offset(16, 16),
      ]) {
        expect(
          pixel(point.dx.toInt(), point.dy.toInt()).a,
          0,
          reason: '$brightness: transparent inset or rounded corner at $point',
        );
      }
    }
  });
}
