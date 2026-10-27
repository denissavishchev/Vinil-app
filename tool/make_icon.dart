// Renders the app icon (the record without the tonearm): flutter test tool/make_icon.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vinil_app/ui/deck.dart';
import 'package:vinil_app/ui/theme.dart';

Future<void> render(String path, {required double fillRatio, required bool background, double size = 1024.0}) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  // dark background, the record gets brighter and thicker lines so it reads at small sizes
  if (background) {
    canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size, size),
        ui.Paint()
          ..shader = ui.Gradient.linear(const ui.Offset(0, 0), ui.Offset(size, size), [const ui.Color(0xFF1B2030), const ui.Color(0xFF0E111A)]));
  }
  // the record in its own 292 x 292 design box, platter diameter 286
  final s = size * fillRatio / 286.0;
  canvas.translate(size / 2, size / 2);
  canvas.scale(s);
  canvas.translate(-146, -146);
  canvas.drawCircle(const ui.Offset(146, 146), 143, fill(navy)); // body of the record
  const box = ui.Size(292, 292);
  RimPainter(false, boost: 1.9).paint(canvas, box);
  const DiscPainter(showText: false, boost: 1.9).paint(canvas, box);
  const SpindlePainter().paint(canvas, box);
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('icon', () async {
    await render('assets/icon/icon.png', fillRatio: 0.98, background: true);
    await render('assets/icon/icon_foreground.png', fillRatio: 0.70, background: false);
    // Android 12+ shows the splash icon inside a circle two thirds of the image wide, so the record must fit in it
    await render('assets/icon/splash12.png', fillRatio: 0.58, background: false);
    await render('assets/icon/splash.png', fillRatio: 0.84, background: false, size: 1536);
  });
}
