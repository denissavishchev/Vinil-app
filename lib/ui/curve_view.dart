import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../dsp/curve.dart';
import '../dsp/engine.dart';
import 'theme.dart';

/// Waveform of the recording + the speed curve. Touch: tap empty space to add a point, drag a point to move it,
/// press and hold a point to delete it.
class CurveView extends StatefulWidget {
  final AppController app;
  const CurveView({super.key, required this.app});

  @override
  State<CurveView> createState() => _CurveViewState();
}

class _CurveViewState extends State<CurveView> {
  static const double _hit = 24.0;
  static const double _lineReach =
      10.0; // a new point needs a touch this close to the curve
  int _drag = -1;
  bool _created = false; // the point being dragged was added by this touch
  int? _pointer;
  Offset _downAt = Offset.zero;
  Timer? _hold;
  String _readout = '';

  // two fingers: zoom and pan the time axis
  final Map<int, Offset> _fingers = {};
  bool _zooming = false, _locked = false;
  double _zoomDist0 = 1, _zoomSpan0 = 1, _zoomFocus = 0;

  AppController get app => widget.app;
  VinilEngine get engine => app.engine;
  List<CurvePoint> get pts => engine.curve.pts;

  // geometry (mirrors the plugin: the area is the view inset by 6, the speed axis is inset by 10 top and bottom)
  Rect _area(Size s) => (Offset.zero & s).deflate(6);
  double _xToPix(Size s, double x) =>
      _area(s).left + (x - app.viewStart) / app.viewSpan * _area(s).width;
  double _uToPix(Size s, double u) {
    final r = _area(s).deflate(10);
    return r.center.dy - u * r.height * 0.5;
  }

  /// time position (0..1 of the recording) under a pixel; may lie outside the visible part for [clamp] false
  double _pixToX(Size s, double px, {bool clamp = true}) {
    final x =
        app.viewStart + (px - _area(s).left) / _area(s).width * app.viewSpan;
    return clamp ? x.clamp(0.0, 1.0) : x;
  }

  double _pixToU(Size s, double py) {
    final r = _area(s).deflate(10);
    return ((r.center.dy - py) / (r.height * 0.5)).clamp(-1.0, 1.0);
  }

  int _hitPoint(Size s, Offset p) {
    var best = -1;
    var bestD = _hit;
    for (var i = 0; i < pts.length; ++i) {
      final d =
          (p - Offset(_xToPix(s, pts[i].x), _uToPix(s, pts[i].y))).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// is the touch on the curve line, or within [_lineReach] pixels of it?
  bool _nearCurve(Size s, Offset p) {
    for (var dx = -_lineReach; dx <= _lineReach; dx += 2) {
      final x = _pixToX(s, p.dx + dx);
      final y = _uToPix(s, engine.curveAt(x));
      if (math.sqrt(dx * dx + (p.dy - y) * (p.dy - y)) <= _lineReach)
        return true;
    }
    return false;
  }

  void _addPoint(Size s, Offset p) {
    final x = _pixToX(s, p.dx), u = _pixToU(s, p.dy);
    var at = pts.indexWhere((q) => q.x > x);
    _drag = -1;
    if (at <= 0) return;
    if (x - pts[at - 1].x < CurveModel.minGap ||
        pts[at].x - x < CurveModel.minGap) {
      return;
    }
    pts.insert(at, CurvePoint(x, u));
    _drag = at;
    _created = true;
    app.curveEdited();
  }

  void _beginZoom(Size s) {
    _hold?.cancel();
    if (_created && _drag > 0 && _drag < pts.length - 1) {
      pts.removeAt(
        _drag,
      ); // the first finger of the pinch only added a point by accident
      app.curveEdited();
    }
    _drag = -1;
    _created = false;
    _pointer = null;
    _readout = '';
    final f = _fingers.values.toList();
    _zoomDist0 = math.max(24.0, (f[0].dx - f[1].dx).abs());
    _zoomSpan0 = app.viewSpan;
    _zoomFocus = _pixToX(s, (f[0].dx + f[1].dx) / 2);
    _zooming = true;
  }

  void _zoomMove(Size s) {
    final f = _fingers.values.toList();
    final dist = math.max(24.0, (f[0].dx - f[1].dx).abs());
    final span = (_zoomSpan0 * _zoomDist0 / dist).clamp(app.minViewSpan, 1.0);
    final mid = (f[0].dx + f[1].dx) / 2;
    // the point of the recording that was between the fingers stays between them
    final start = _zoomFocus - (mid - _area(s).left) / _area(s).width * span;
    app.viewSpan = span;
    app.viewStart = start.clamp(0.0, 1.0 - span);
    setState(() {});
  }

  void _down(Size s, PointerDownEvent e) {
    final canZoom = app.hasClip && !app.recording;
    if (_fingers.length < 2 && _area(s).contains(e.localPosition))
      _fingers[e.pointer] = e.localPosition;
    if (canZoom && _fingers.length == 2 && !_zooming) {
      _beginZoom(s);
      setState(() {});
      return;
    }
    if (_zooming || _locked || _fingers.length != 1 || _pointer != null) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    final idx = _hitPoint(s, e.localPosition);
    if (idx >= 0) {
      _drag = idx;
      if (idx > 0 && idx < pts.length - 1) {
        _hold = Timer(const Duration(milliseconds: 600), () {
          if (_drag > 0 && _drag < pts.length - 1) {
            pts.removeAt(_drag);
            _drag = -1;
            _readout = '';
            app.curveEdited();
          }
        });
      }
    } else if (_nearCurve(s, e.localPosition)) {
      _addPoint(s, e.localPosition);
    }
    setState(() {});
  }

  void _move(Size s, PointerMoveEvent e) {
    if (_fingers.containsKey(e.pointer)) _fingers[e.pointer] = e.localPosition;
    if (_zooming) {
      if (_fingers.length == 2) _zoomMove(s);
      return;
    }
    if (e.pointer != _pointer) return;
    if ((e.localPosition - _downAt).distance > 6) _hold?.cancel();
    if (_drag < 0 || _drag >= pts.length) return;
    final x = _pixToX(s, e.localPosition.dx),
        u = _pixToU(s, e.localPosition.dy);
    final pt = pts[_drag];
    pt.y = u;
    if (_drag > 0 && _drag < pts.length - 1) {
      pt.x = x.clamp(
        pts[_drag - 1].x + CurveModel.minGap,
        pts[_drag + 1].x - CurveModel.minGap,
      );
    }
    final speed = u * VinilEngine.speedRange;
    _readout =
        '${(pt.x * app.clipSeconds).toStringAsFixed(2)} s   ${speed >= 0 ? '+' : ''}${speed.toStringAsFixed(2)}x';
    app.curveEdited();
  }

  void _up(PointerEvent e) {
    _fingers.remove(e.pointer);
    if (_zooming) {
      if (_fingers.length < 2) {
        _zooming = false;
        _locked = true; // the finger that is left does not edit anything
      }
    }
    if (_fingers.isEmpty) _locked = false;
    if (e.pointer != _pointer) return;
    _hold?.cancel();
    _pointer = null;
    _drag = -1;
    _created = false;
    _readout = '';
    setState(() {});
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final curveLayer = CustomPaint(
          size: size,
          painter: _CurveLinePainter(widget.app, _drag),
        );
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(size, e),
          onPointerMove: (e) => _move(size, e),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(
            children: [
              // the grid, waveform and curve are painted only when something changes; the playhead has its own layer
              RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: _CurvePainter(widget.app, _drag, _readout),
                ),
              ),
              // the curve fades while the record is being scratched
              // (the painted child is built once per rebuild, so the per-frame opacity change does not repaint it)
              RepaintBoundary(
                child: Frames(
                  builder: (_) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: widget.app.engine.scratching ? 0.25 : 1.0,
                    child: curveLayer,
                  ),
                ),
              ),
              if (widget.app.hasClip && !widget.app.recording)
                RepaintBoundary(
                  child: Frames(
                    builder: (_) => CustomPaint(
                      size: size,
                      painter: _PlayheadPainter(widget.app),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  final AppController app;
  final int dragIndex;
  final String readout;
  _CurvePainter(this.app, this.dragIndex, this.readout);

  VinilEngine get engine => app.engine;

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(all, const Radius.circular(12)),
      fill(navyLo),
    );

    final area = all.deflate(6);
    final inner = area.deflate(10);
    final v0 = app.viewStart, span = app.viewSpan;
    double xToPix(double x) => area.left + (x - v0) / span * area.width;
    double uToPix(double u) => inner.center.dy - u * inner.height * 0.5;
    final cy = uToPix(0);
    const range = VinilEngine.speedRange;

    canvas.save();
    canvas.clipRect(area);

    // ---- speed grid ----
    for (var s = -range.toInt(); s <= range.toInt(); ++s) {
      final y = uToPix(s / range);
      if (s == 0) {
        final p = stroke(gold.withValues(alpha: 0.55), 1);
        for (var x = area.left; x < area.right; x += 9) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + 5, area.right), y),
            p,
          );
        }
      } else {
        canvas.drawLine(
          Offset(area.left, y),
          Offset(area.right, y),
          stroke(gold.withValues(alpha: 0.16), 1),
        );
      }
      drawText(
        canvas,
        '${s > 0 ? '+' : ''}${s}x',
        Offset(area.left + 3, y - 6),
        mono(9.5, gold.withValues(alpha: 0.6)),
        align: -1,
      );
    }

    // ---- time axis in seconds (of the visible part) ----
    final dur = app.clipSeconds;
    final shown = dur * span;
    // labels at least ~36 px apart
    var step = 10.0;
    for (final cand in const [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0]) {
      if (area.width * cand / shown >= 36) {
        step = cand;
        break;
      }
    }
    final t0 = v0 * dur, t1 = (v0 + span) * dur;
    final atEnd = v0 + span > 0.999;
    for (var t = (t0 / step).ceil() * step; t < t1 - 0.001; t += step) {
      final x = xToPix(t / dur);
      canvas.drawLine(
        Offset(x, area.top),
        Offset(x, area.bottom),
        stroke(gold.withValues(alpha: 0.12), 1),
      );
      if (area.right - x < 40 && atEnd) continue;
      drawText(
        canvas,
        step < 1 ? '${t.toStringAsFixed(1)}s' : '${t.round()}s',
        Offset(x + 3, area.bottom - 8),
        mono(9.5, gold.withValues(alpha: 0.65)),
        align: -1,
      );
    }
    if (atEnd) {
      drawText(
        canvas,
        '${dur.toStringAsFixed(dur == dur.roundToDouble() ? 0 : 1)}s',
        Offset(area.right - 3, area.bottom - 8),
        mono(9.5, gold.withValues(alpha: 0.65)),
        align: 1,
      );
    }

    // ---- waveform of the recording ----
    if (app.hasClip || app.recording) {
      final wp = fill(gold.withValues(alpha: 0.3));
      final cols = area.width.toInt();
      final hh = area.height * 0.42;
      // display only: stretch the drawing so the loudest part reaches ~90% of the height (the audio is not touched)
      var peak = 0.0;
      for (final v in app.wave) {
        if (v > peak) peak = v;
      }
      final gain = (0.9 / math.max(peak, 0.15)).clamp(1.0, 6.0);
      for (var x = 0; x < cols; x += 2) {
        final a =
            gain *
            app.wave[math.min(
              VinilEngine.waveBins - 1,
              ((v0 + x / math.max(1, cols) * span) * VinilEngine.waveBins)
                  .toInt(),
            )];
        canvas.drawRect(
          Rect.fromLTWH(
            area.left + x,
            cy - math.min(a, 1.0) * hh,
            1.6,
            math.max(1.0, math.min(a, 1.0) * hh * 2.0),
          ),
          wp,
        );
      }
    }

    final note =
        app.message ??
        (!app.hasClip && !app.recording ? 'PRESS REC  -  MAX 20 s' : null);
    if (note != null) {
      drawText(
        canvas,
        note,
        Offset(area.center.dx, area.center.dy - 26),
        mono(11, goldHi.withValues(alpha: 0.8), bold: true),
      );
    }
    if (app.recording) {
      drawText(
        canvas,
        'REC',
        Offset(area.right - 8, area.top + 12),
        mono(10.5, goldHi, bold: true),
        align: 1,
      );
    }
    canvas.restore();

    if (readout.isNotEmpty) {
      drawText(
        canvas,
        readout,
        Offset(area.right - 8, area.top + 12),
        mono(10.5, goldHi),
        align: 1,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(all.deflate(0.5), const Radius.circular(12)),
      stroke(gold.withValues(alpha: 0.55), 1.2),
    );
  }
}

class _CurveLinePainter extends CustomPainter {
  final AppController app;
  final int dragIndex;
  _CurveLinePainter(this.app, this.dragIndex);

  VinilEngine get engine => app.engine;

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final area = (Offset.zero & size).deflate(6);
    final inner = area.deflate(10);
    final v0 = app.viewStart, span = app.viewSpan;
    double xToPix(double x) => area.left + (x - v0) / span * area.width;
    double uToPix(double u) => inner.center.dy - u * inner.height * 0.5;
    final cy = uToPix(0);
    canvas.save();
    canvas.clipRect(area);

    final path = Path();
    for (var i = 0; i < 512; ++i) {
      final ph = v0 + span * i / 511.0;
      final x = xToPix(ph), y = uToPix(engine.curveAt(ph));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillP = Path.from(path)
      ..lineTo(xToPix(v0 + span), cy)
      ..lineTo(xToPix(v0), cy)
      ..close();
    canvas.drawPath(fillP, fill(gold.withValues(alpha: 0.18)));
    canvas.drawPath(
      path,
      stroke(goldHi, 2.4)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < engine.curve.pts.length; ++i) {
      final pt = engine.curve.pts[i];
      final p = Offset(xToPix(pt.x), uToPix(pt.y));
      canvas.drawCircle(p, 6.5, fill(i == dragIndex ? goldHi : navy));
      canvas.drawCircle(p, 6.5, stroke(goldHi, 1.8));
    }

    canvas.restore();
  }
}

class _PlayheadPainter extends CustomPainter {
  final AppController app;
  _PlayheadPainter(this.app);
  VinilEngine get engine => app.engine;

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final area = (Offset.zero & size).deflate(6);
    final inner = area.deflate(10);
    // the line runs with the curve; it follows the record while it is turned by hand and stands still when the platter is stopped
    final ph = engine.scratching || !engine.motorOn
        ? engine.playPhase
        : engine.cyclePhase;
    final x = area.left + (ph - app.viewStart) / app.viewSpan * area.width;
    canvas.save();
    canvas.clipRect(area);
    canvas.drawLine(
      Offset(x, area.top),
      Offset(x, area.bottom),
      stroke(goldHi.withValues(alpha: 0.9), 1),
    );
    canvas.drawCircle(
      Offset(
        x,
        inner.center.dy -
            // on the curve; while the record is scratched it shows the real speed
            (engine.scratching
                    ? (engine.speedNow / VinilEngine.speedRange).clamp(
                        -1.0,
                        1.0,
                      )
                    : engine.curveAt(ph)) *
                inner.height *
                0.5,
      ),
      3.5,
      fill(goldHi),
    );
    canvas.restore();
  }
}
