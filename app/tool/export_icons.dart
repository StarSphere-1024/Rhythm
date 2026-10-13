import 'dart:io';
import 'dart:typed_data';

const _samplesPerAxis = 4;

class _Rect {
  const _Rect(this.left, this.top, this.right, this.bottom, this.radius);
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double radius;
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}

class _Artwork {
  const _Artwork({
    required this.background,
    required this.foreground,
    required this.backgroundRect,
    required this.checkColor,
    required this.blocks,
    required this.check,
    required this.strokeWidth,
  });

  final List<int> background;
  final List<int> foreground;
  final _Rect backgroundRect;
  final List<int> checkColor;
  final List<_Rect> blocks;
  final List<_Point> check;
  final double strokeWidth;
}

Future<void> main() async {
  final source = File('assets/icons/rhythm.svg');
  if (!source.existsSync()) {
    stderr.writeln('Run this command from the app/ directory.');
    exitCode = 2;
    return;
  }
  final artwork = _parseArtwork(await source.readAsString());
  final outputs = <(int, String, bool)>[
    (48, 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png', false),
    (72, 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png', false),
    (96, 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', false),
    (144, 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', false),
    (192, 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', false),
    (32, 'web/favicon.png', false),
    (192, 'web/icons/Icon-192.png', false),
    (512, 'web/icons/Icon-512.png', false),
    (192, 'web/icons/Icon-maskable-192.png', true),
    (512, 'web/icons/Icon-maskable-512.png', true),
  ];
  final images = <(int, bool), Uint8List>{};
  for (final (size, path, maskable) in outputs) {
    final image = images.putIfAbsent((
      size,
      maskable,
    ), () => _renderPng(artwork, size, maskable: maskable));
    await File(path).writeAsBytes(image);
    stdout.writeln('$path (${size}x$size)');
  }
}

_Artwork _parseArtwork(String source) {
  final viewBox = RegExp(r'<svg\b[^>]*\bviewBox="([^"]+)"').firstMatch(source);
  if (viewBox?.group(1) != '0 0 100 100') {
    throw const FormatException('Expected a 100 x 100 SVG viewBox.');
  }
  final backgroundGroup = _group(source, 'background');
  final foregroundGroup = _group(source, 'foreground');
  final backgroundRects = RegExp(r'<rect\b([^>]*)/?>')
      .allMatches(backgroundGroup)
      .toList();
  if (backgroundRects.length != 1) {
    throw const FormatException('Expected one rounded background rect.');
  }
  final backgroundAttrs = _attributes(backgroundRects.single.group(1)!);
  final backgroundRect = _Rect(
    double.parse(backgroundAttrs['x']!),
    double.parse(backgroundAttrs['y']!),
    double.parse(backgroundAttrs['x']!) +
        double.parse(backgroundAttrs['width']!),
    double.parse(backgroundAttrs['y']!) +
        double.parse(backgroundAttrs['height']!),
    double.parse(backgroundAttrs['rx']!),
  );
  final background = _hexColor(backgroundAttrs['fill']!);
  final foregroundGroupAttrs = _attributes(
    RegExp(r'<g\b([^>]*)>').firstMatch(foregroundGroup)!.group(1)!,
  );
  final foregroundColor = _hexColor(foregroundGroupAttrs['fill']!);

  final blockMatches = RegExp(r'<rect\b([^>]*)/?>')
      .allMatches(foregroundGroup)
      .toList();
  final blocks = <_Rect>[];
  for (final match in blockMatches) {
    final attrs = _attributes(match.group(1)!);
    blocks.add(
      _Rect(
        double.parse(attrs['x']!),
        double.parse(attrs['y']!),
        double.parse(attrs['x']!) + double.parse(attrs['width']!),
        double.parse(attrs['y']!) + double.parse(attrs['height']!),
        double.parse(attrs['rx']!),
      ),
    );
  }
  final paths = RegExp(r'<path\b([^>]*)/?>')
      .allMatches(foregroundGroup)
      .toList();
  if (blocks.length != 3 || paths.length != 1) {
    throw const FormatException(
      'Expected three time blocks and one check path.',
    );
  }
  final checkAttrs = _attributes(paths.single.group(1)!);
  if (checkAttrs['stroke-linecap'] != 'round' ||
      checkAttrs['stroke-linejoin'] != 'round' ||
      checkAttrs['fill'] != 'none') {
    throw const FormatException('Check must be an unfilled rounded stroke.');
  }
  final checkColor = _hexColor(checkAttrs['stroke']!);
  const number = r'[-+]?(?:\d*\.\d+|\d+\.?\d*)';
  if (!RegExp(
    '^M\\s*$number[\\s,]+$number\\s+'
    'L\\s*$number[\\s,]+$number\\s+'
    'L\\s*$number[\\s,]+$number\\s*\$',
  ).hasMatch(checkAttrs['d']!)) {
    throw const FormatException('Expected a three-point M/L check path.');
  }
  final coordinates = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)')
      .allMatches(checkAttrs['d']!)
      .map((match) => double.parse(match.group(0)!))
      .toList();
  if (coordinates.length != 6) {
    throw const FormatException('Expected a three-point check path.');
  }
  final check = <_Point>[
    for (var i = 0; i < coordinates.length; i += 2)
      _Point(coordinates[i], coordinates[i + 1]),
  ];
  return _Artwork(
    background: background,
    foreground: foregroundColor,
    backgroundRect: backgroundRect,
    checkColor: checkColor,
    blocks: blocks,
    check: check,
    strokeWidth: double.parse(checkAttrs['stroke-width']!),
  );
}

String _group(String source, String id) {
  final match = RegExp(
    '<g\\b(?=[^>]*\\bid="$id")[^>]*>(.*?)</g>',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) throw FormatException('Missing SVG group "$id".');
  return match.group(0)!;
}

Map<String, String> _attributes(String source) => {
  for (final match in RegExp(r'([\w-]+)="([^"]*)"').allMatches(source))
    match.group(1)!: match.group(2)!,
};

List<int> _hexColor(String value) {
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6) throw FormatException('Expected #RRGGBB: $value');
  return [
    int.parse(hex.substring(0, 2), radix: 16),
    int.parse(hex.substring(2, 4), radix: 16),
    int.parse(hex.substring(4, 6), radix: 16),
  ];
}

Uint8List _renderPng(_Artwork artwork, int size, {required bool maskable}) {
  final rgba = Uint8List(size * size * 4);
  final scale = 100 / size;
  const sampleCount = _samplesPerAxis * _samplesPerAxis;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var backgroundSamples = 0;
      var blockSamples = 0;
      var checkSamples = 0;
      for (var sy = 0; sy < _samplesPerAxis; sy++) {
        for (var sx = 0; sx < _samplesPerAxis; sx++) {
          final px = (x + (sx + 0.5) / _samplesPerAxis) * scale;
          final py = (y + (sy + 0.5) / _samplesPerAxis) * scale;
          if (_isCheck(artwork, px, py)) {
            checkSamples++;
          } else if (_isBlock(artwork, px, py)) {
            blockSamples++;
          } else if (maskable ||
              _containsRect(artwork.backgroundRect, px, py)) {
            backgroundSamples++;
          }
        }
      }
      final covered = backgroundSamples + blockSamples + checkSamples;
      final offset = (y * size + x) * 4;
      if (covered == 0) continue;
      for (var channel = 0; channel < 3; channel++) {
        rgba[offset + channel] =
            ((artwork.background[channel] * backgroundSamples +
                        artwork.foreground[channel] * blockSamples +
                        artwork.checkColor[channel] * checkSamples) /
                    covered)
                .round();
      }
      rgba[offset + 3] = (255 * covered / sampleCount).round();
    }
  }
  return _encodePng(size, size, rgba);
}

bool _containsRect(_Rect rect, double x, double y) {
  final closestX = x.clamp(rect.left + rect.radius, rect.right - rect.radius);
  final closestY = y.clamp(rect.top + rect.radius, rect.bottom - rect.radius);
  final dx = x - closestX;
  final dy = y - closestY;
  return dx * dx + dy * dy <= rect.radius * rect.radius;
}

bool _isBlock(_Artwork artwork, double x, double y) {
  for (var i = 0; i < artwork.blocks.length; i++) {
    if (_containsRect(artwork.blocks[i], x, y)) return true;
  }
  return false;
}

bool _isCheck(_Artwork artwork, double x, double y) {
  final radius = artwork.strokeWidth / 2;
  for (var i = 0; i < artwork.check.length - 1; i++) {
    final start = artwork.check[i];
    final end = artwork.check[i + 1];
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;
    final t = (((x - start.x) * dx + (y - start.y) * dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    final nearX = start.x + t * dx;
    final nearY = start.y + t * dy;
    final deltaX = x - nearX;
    final deltaY = y - nearY;
    if (deltaX * deltaX + deltaY * deltaY <= radius * radius) return true;
  }
  return false;
}

Uint8List _encodePng(int width, int height, Uint8List rgba) {
  final scanlines = Uint8List(height * (width * 4 + 1));
  for (var y = 0; y < height; y++) {
    final row = y * (width * 4 + 1);
    scanlines[row] = 0;
    scanlines.setRange(row + 1, row + 1 + width * 4, rgba, y * width * 4);
  }
  final output = BytesBuilder(copy: false)
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _addChunk(output, 'IHDR', header.buffer.asUint8List());
  _addChunk(output, 'IDAT', ZLibEncoder().convert(scanlines));
  _addChunk(output, 'IEND', const []);
  return output.takeBytes();
}

void _addChunk(BytesBuilder output, String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  output
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data);
  var crc = 0xffffffff;
  for (final byte in [...typeBytes, ...data]) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
  output.add(checksum.buffer.asUint8List());
}
