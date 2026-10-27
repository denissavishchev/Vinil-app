import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dsp/engine.dart';
import 'controls.dart';
import 'theme.dart';

const double kDeckW = 372,
    kDeckH = 306; // design size of the record and the tonearm
const double _twoPi = 2 * math.pi;

/// The turntable panel: the record and tonearm in the plugin's own design size, scaled to fit, and one play / stop button.
class Deck extends StatefulWidget {
  static const double _pad = 6;
  final VinilEngine engine;
  const Deck({super.key, required this.engine});

  /// panel height for a given panel width
  static double heightFor(double width) => (width - 2 * _pad) * kDeckH / kDeckW + 2 * _pad;

  @override
  State<Deck> createState() => _DeckState();
}

class _DeckState extends State<Deck> {
  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    return Panel(
      padding: const EdgeInsets.all(Deck._pad),
      child: Stack(children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: kDeckW,
              height: kDeckH,
              child: Stack(children: [
                Positioned(left: 8, top: 8, width: 292, height: 292, child: Turntable(engine: engine)),
                const Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _TonearmPainter())))),
              ]),
            ),
          ),
        ),
        // shows what a tap does: stop while it plays, play while it is stopped
        Positioned(
          right: 6,
          bottom: 6,
          width: 42,
          height: 42,
          child: IconSquareButton(play: !engine.motorOn, onTap: () => setState(() => engine.motorOn = !engine.motorOn)),
        ),
      ]),
    );
  }
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const pivot = Offset(kDeckW - 40, 46);
    final elbow = Offset(pivot.dx - 4, pivot.dy + 112);
    const head = Offset(262, 232);

    canvas.drawCircle(pivot, 17, fill(navy));
    canvas.drawCircle(pivot, 17, stroke(gold, 2));
    canvas.drawCircle(pivot, 6, fill(gold));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pivot.dx - 7, pivot.dy - 42, 14, 24),
        const Radius.circular(3),
      ),
      stroke(gold, 1.6),
    );

    final arm = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..lineTo(elbow.dx, elbow.dy)
      ..lineTo(head.dx, head.dy);
    for (final p in [stroke(navy, 7), stroke(gold, 3)]) {
      canvas.drawPath(
        arm,
        p
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final a = math.atan2(head.dy - elbow.dy, head.dx - elbow.dx);
    canvas.save();
    canvas.translate(head.dx - math.cos(a) * 2, head.dy - math.sin(a) * 2);
    canvas.rotate(a);
    final shell = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-4, -6, 24, 12),
      const Radius.circular(2),
    );
    canvas.drawRRect(shell, fill(navy));
    canvas.drawRRect(shell, stroke(gold, 1.8));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The record: grab it and scratch.
class Turntable extends StatefulWidget {
  final VinilEngine engine;
  const Turntable({super.key, required this.engine});
  @override
  State<Turntable> createState() => _TurntableState();
}

class _TurntableState extends State<Turntable> {
  int? _pointer;
  double _lastAngle = 0;

  double _angleAt(Size s, Offset p) =>
      math.atan2(p.dy - s.height / 2, p.dx - s.width / 2);

  bool _inside(Size s, Offset p) {
    final b = (Offset.zero & s).deflate(3);
    return (p - b.center).distance <= math.min(b.width, b.height) * 0.5;
  }

  void _down(Size s, PointerDownEvent e) {
    if (_pointer != null || !_inside(s, e.localPosition)) return;
    _pointer = e.pointer;
    _lastAngle = _angleAt(s, e.localPosition);
    widget.engine.grabbed = true;
    setState(() {});
  }

  void _move(Size s, PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final a = _angleAt(s, e.localPosition);
    var d = a - _lastAngle;
    if (d > math.pi) d -= _twoPi;
    if (d < -math.pi) d += _twoPi;
    _lastAngle = a;
    widget.engine.addPlatterAngle(d);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    widget.engine.grabbed = false;
    setState(() {});
  }

  @override
  void dispose() {
    widget.engine.grabbed = false;
    super.dispose();
  }

  // the disc is rasterised once and only rotated, so spinning costs almost nothing
  static const Widget _disc = RepaintBoundary(
    child: CustomPaint(painter: DiscPainter(), child: SizedBox.expand()),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(size, e),
          onPointerMove: (e) => _move(size, e),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: RimPainter(_pointer != null),
                ),
              ),
              Frames(
                builder: (_) => Transform.rotate(
                  angle: widget.engine.platterAngle,
                  child: _disc,
                ),
              ),
              const IgnorePointer(
                child: CustomPaint(
                  painter: SpindlePainter(),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class RimPainter extends CustomPainter {
  final bool held;
  final double boost; // > 1 for the app icon: brighter, thicker lines
  RimPainter(this.held, {this.boost = 1.0});

  @override
  bool shouldRepaint(covariant RimPainter old) => old.held != held || old.boost != boost;

  @override
  void paint(Canvas canvas, Size size) {
    final b = (Offset.zero & size).deflate(3);
    final c = b.center;
    final r = math.min(b.width, b.height) * 0.5;
    if (held) canvas.drawCircle(c, r, fill((boost > 1 ? goldHi : gold).withValues(alpha: math.min(1.0, 0.14 * boost))));
    canvas.drawCircle(c, r, stroke(boost > 1 ? goldHi : gold, 2.4 * boost));
    canvas.drawCircle(c, r - 7, stroke((boost > 1 ? goldHi : gold).withValues(alpha: math.min(1.0, 0.45 * boost)), 1));
  }
}

class SpindlePainter extends CustomPainter {
  const SpindlePainter();

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(size.center(Offset.zero), 3.5, fill(goldHi));
}

class DiscPainter extends CustomPainter {
  final bool showText; // off for the app icon
  final double boost; // > 1 for the app icon: brighter, thicker lines
  const DiscPainter({this.showText = true, this.boost = 1.0});

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final tone = boost > 1 ? goldHi : gold;
    final b = (Offset.zero & size).deflate(3);
    final c = b.center;
    final r = math.min(b.width, b.height) * 0.5;

    // grooves
    var k = 0;
    for (var rr = r * 0.40; rr < r * 0.90; rr += 3.6, ++k) {
      canvas.drawCircle(
        c,
        rr,
        stroke(tone.withValues(alpha: math.min(1.0, (k % 4 == 0 ? 0.26 : 0.12) * boost)), 0.9),
      );
    }
    for (final rr in [r * 0.60, r * 0.77]) {
      canvas.drawCircle(c, rr, stroke(tone.withValues(alpha: math.min(1.0, (0.55) * boost)), 1.6));
    }

    // strobe ticks along the rim
    for (var i = 0; i < 72; ++i) {
      final a = _twoPi * i / 72.0;
      final major = i % 6 == 0;
      final r0 = r * (major ? 0.915 : 0.945), r1 = r * 0.97;
      canvas.drawLine(
        Offset(c.dx + math.sin(a) * r0, c.dy - math.cos(a) * r0),
        Offset(c.dx + math.sin(a) * r1, c.dy - math.cos(a) * r1),
        stroke(tone.withValues(alpha: math.min(1.0, (major ? 0.9 : 0.5) * boost)), major ? 1.8 : 1.0),
      );
    }

    // shine wedges: they make the rotation easy to read (angles from 12 o'clock, clockwise)
    for (var s = 0; s < 2; ++s) {
      final rr = r * 0.84, a0 = s * math.pi - 0.28 - math.pi / 2;
      final wedge = Path()
        ..addArc(Rect.fromCircle(center: c, radius: rr), a0, 0.56);
      canvas.drawPath(
        wedge,
        stroke(tone.withValues(alpha: math.min(1.0, (0.3) * boost)), 5)..strokeCap = StrokeCap.round,
      );
    }

    // label: VINIL above the spindle, the notch below it, both on the centre line
    final rl = r * 0.30;
    canvas.drawCircle(c, rl, fill(navyHi));
    canvas.drawCircle(c, rl, stroke(tone, 2 * boost));
    canvas.drawCircle(c, rl * 0.82, stroke(tone, 0.8 * boost));
    if (showText) drawText(canvas, 'VINIL', Offset(c.dx, c.dy - rl * 0.36), sans(r * 0.105, gold));
    final notch = Path()
      ..moveTo(c.dx, c.dy + rl * 0.2)
      ..lineTo(c.dx - 5, c.dy + rl * 0.2 + 10)
      ..lineTo(c.dx + 5, c.dy + rl * 0.2 + 10)
      ..close();
    if (showText) canvas.drawPath(notch, fill(tone)); // the app icon has neither the text nor the notch
  }
}
