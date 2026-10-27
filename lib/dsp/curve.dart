import 'dart:math' as math;
import 'dart:typed_data';

/// One breakpoint of the speed curve. x = position inside the loop 0..1,
/// y = playback speed divided by the range, -1..1 (so +-1 is always the top / bottom of the display).
class CurvePoint {
  double x, y;
  CurvePoint(this.x, this.y);
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

class CurveModel {
  static const int lutSize = 1024;
  static const double minGap = 0.002;

  List<CurvePoint> pts = [];

  CurveModel() {
    reset(0.5);
  }

  void reset(double u) => pts = [CurvePoint(0, u), CurvePoint(1, u)];

  /// Samples the curve into out[0..n-1]; smooth = monotone cubic (no overshoot between points), otherwise straight lines.
  void bake(Float32List out, int n, bool smooth) {
    final np = pts.length;
    if (np < 2) {
      for (var i = 0; i < n; ++i) {
        out[i] = np == 1 ? pts[0].y : 0.0;
      }
      return;
    }

    final h = List<double>.filled(np - 1, 0),
        d = List<double>.filled(np - 1, 0),
        m = List<double>.filled(np, 0);
    for (var k = 0; k < np - 1; ++k) {
      h[k] = math.max(1.0e-6, pts[k + 1].x - pts[k].x);
      d[k] = (pts[k + 1].y - pts[k].y) / h[k];
    }
    if (smooth) {
      m[0] = d[0];
      m[np - 1] = d[np - 2];
      for (var k = 1; k < np - 1; ++k) {
        final a = d[k - 1], b = d[k];
        if (a * b <= 0.0) {
          m[k] = 0.0;
          continue;
        }
        final w1 = 2.0 * h[k] + h[k - 1];
        final w2 = h[k] + 2.0 * h[k - 1];
        m[k] = (w1 + w2) / (w1 / a + w2 / b);
      }
    }

    var seg = 0;
    for (var i = 0; i < n; ++i) {
      final x = n > 1 ? i / (n - 1) : 0.0;
      while (seg < np - 2 && x > pts[seg + 1].x) {
        ++seg;
      }
      final p0 = pts[seg], p1 = pts[seg + 1];
      final hh = h[seg];
      final t = _clamp((x - p0.x) / hh, 0.0, 1.0);
      double y;
      if (smooth) {
        final t2 = t * t, t3 = t2 * t;
        y =
            (2 * t3 - 3 * t2 + 1) * p0.y +
            (t3 - 2 * t2 + t) * hh * m[seg] +
            (-2 * t3 + 3 * t2) * p1.y +
            (t3 - t2) * hh * m[seg + 1];
      } else {
        y = p0.y + (p1.y - p0.y) * t;
      }
      out[i] = _clamp(y, -1.0, 1.0);
    }
  }

  String serialize() => pts
      .map((p) => '${p.x.toStringAsFixed(5)},${p.y.toStringAsFixed(5)}')
      .join(';');

  void deserialize(String s) {
    final v = <CurvePoint>[];
    for (final tok in s.split(';')) {
      final xy = tok.split(',');
      if (xy.length == 2) {
        final x = double.tryParse(xy[0]), y = double.tryParse(xy[1]);
        if (x != null && y != null)
          v.add(CurvePoint(_clamp(x, 0, 1), _clamp(y, -1, 1)));
      }
    }
    if (v.length < 2 || v.first.x > 0.0001 || v.last.x < 0.9999) {
      reset(0.5);
      return;
    }
    for (var i = 1; i < v.length; ++i) {
      if (v[i].x <= v[i - 1].x) {
        reset(0.5);
        return;
      }
    }
    pts = v;
  }
}

/// Ready-made curve shapes (the pads); speeds are in x-speed units, scaled to the current range.
class Shapes {
  static const names = [
    'FLAT',
    'SINE',
    'TRI',
    'SAW',
    'SQR',
    'STOP',
    'START',
    'REV',
    'BABY',
    'CHIRP',
    'GATE',
    'PULSE',
    'BACKSPIN',
    'STUTTER',
    'WOBBLE',
    'STAIRS',
  ];

  /// The pads, in this order (indices into [make]).
  static const padShapes = [0, 1, 3, 4, 5, 6, 7, 8, 10, 11, 15, 9, 12, 13, 14];

  static List<CurvePoint> make(int idx, double range) {
    const twoPi = 2 * math.pi;
    final v = <CurvePoint>[];
    void add(double x, double speed) =>
        v.add(CurvePoint(x, _clamp(speed / range, -1.0, 1.0)));
    void sampled(int n, double Function(double) f) {
      for (var i = 0; i <= n; ++i) {
        final x = i / n;
        add(x, f(x));
      }
    }

    double smoothstep(double t) {
      t = _clamp(t, 0.0, 1.0);
      return t * t * (3.0 - 2.0 * t);
    }

    switch (idx) {
      case 0:
        add(0.0, 1.0);
        add(1.0, 1.0);
      case 1:
        sampled(16, (x) => 1.5 * math.sin(twoPi * x));
      case 2:
        add(0.0, 0.0);
        add(0.25, 1.5);
        add(0.75, -1.5);
        add(1.0, 0.0);
      case 3:
        add(0.0, -1.5);
        add(1.0, 1.5);
      case 4:
        add(0.0, 1.5);
        add(0.498, 1.5);
        add(0.502, -1.5);
        add(1.0, -1.5);
      case 5:
        sampled(10, (x) {
          final t = math.max(0.0, 1.0 - x / 0.7);
          return t * t;
        });
      case 6:
        sampled(10, (x) => smoothstep(x / 0.7));
      case 7:
        add(0.0, -1.0);
        add(1.0, -1.0);
      case 8:
        sampled(24, (x) => 1.6 * math.sin(twoPi * 2.0 * x));
      case 9:
        sampled(32, (x) => 1.2 * math.sin(twoPi * 4.0 * x));
      case 10:
        for (var k = 0; k < 8; ++k) {
          final s = (k % 2 == 0) ? 1.0 : 0.0;
          add(k / 8.0 + (k > 0 ? 0.003 : 0.0), s);
          add((k + 1) / 8.0 - (k < 7 ? 0.003 : 0.0), s);
        }
      case 12: // BACKSPIN: from -2x, quickly settling to +1x
        for (var i = 0; i <= 20; ++i) {
          final x = (i / 20.0) * (i / 20.0);
          add(x, 1.0 - 3.0 * math.exp(-x / 0.06));
        }
      case 13: // STUTTER: +1x, 0, -1x, 0 on every 1/16 of the loop
        const pattern = [1.0, 0.0, -1.0, 0.0];
        for (var k = 0; k < 16; ++k) {
          final sp = pattern[k % 4];
          add(k / 16.0 + (k > 0 ? 0.003 : 0.0), sp);
          add((k + 1) / 16.0 - (k < 15 ? 0.003 : 0.0), sp);
        }
      case 14: // WOBBLE: slow, shallow speed drift around normal
        sampled(24, (x) => 1.0 + 0.3 * math.sin(twoPi * 2.0 * x));
      case 15: // STAIRS: 0, 0.5x, 1x, 1.5x, 2x, each held for a fifth of the loop
        for (var k = 0; k < 5; ++k) {
          final sp = k * 0.5;
          add(k / 5.0 + (k > 0 ? 0.003 : 0.0), sp);
          add((k + 1) / 5.0 - (k < 4 ? 0.003 : 0.0), sp);
        }
      default:
        sampled(36, (x) => 1.6 * (math.sin(math.pi * 3.0 * x)).abs());
    }
    return v;
  }
}
