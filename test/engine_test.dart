import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinil_app/audio/wav.dart';
import 'package:vinil_app/dsp/curve.dart';
import 'package:vinil_app/dsp/engine.dart';

const sr = 44100;
const bs = 256;

Float32List tone(double seconds) {
  final n = (seconds * sr).round();
  return Float32List.fromList([for (var i = 0; i < n; ++i) 0.5 * math.sin(2 * math.pi * 440.0 * i / sr)]);
}

class Run {
  final out = <double>[];
  double maxJump = 0.0;
  bool bad = false;
}

Run render(VinilEngine e, int blocks, [void Function(int)? perBlock]) {
  final r = Run();
  final buf = Float32List(bs);
  double prev = 0.0;
  var first = true;
  for (var b = 0; b < blocks; ++b) {
    perBlock?.call(b);
    e.process(buf, bs);
    for (var i = 0; i < bs; ++i) {
      final o = buf[i];
      if (!o.isFinite || o.abs() > 2.0) r.bad = true;
      if (!first) r.maxJump = math.max(r.maxJump, (o - prev).abs());
      first = false;
      prev = o;
      r.out.add(o);
    }
  }
  return r;
}

VinilEngine make(double seconds) => VinilEngine(sampleRate: sr)
  ..motorOn = true
  ..setClip(tone(seconds));

void main() {
  test('untouched is transparent (2-sample delay)', () {
    final e = make(5);
    final r = render(e, 200);
    var err = 0.0;
    for (var i = 100; i < r.out.length; ++i) {
      final expect = 0.5 * math.sin(2 * math.pi * 440.0 * (i - 2) / sr);
      err = math.max(err, (r.out[i] - expect).abs());
    }
    expect(r.bad, false);
    expect(err, lessThan(1e-3));
  });

  test('scratching: no clicks, head lags, plays on after release', () {
    final e = make(5);
    var lagMax = 0.0;
    final r = render(e, 400, (b) {
      if (b == 40) e.grabbed = true;
      if (b >= 40 && b < 80) e.addPlatterAngle(-0.05);
      if (b >= 80 && b < 120) e.addPlatterAngle(0.06);
      if (b == 120) e.grabbed = false;
      lagMax = math.max(lagMax, e.lagSeconds);
    });
    expect(r.bad, false);
    expect(r.maxJump, lessThan(0.13));
    expect(lagMax, greaterThan(0.3));
    expect((e.speedNow - 1.0).abs(), lessThan(0.02));
    expect(e.lagSeconds, greaterThan(0.0));
  });

  test('holding the record still silences the output', () {
    final e = make(5);
    final r = render(e, 100, (b) {
      if (b == 20) e.grabbed = true;
    });
    var tail = 0.0;
    for (var i = r.out.length - 2000; i < r.out.length; ++i) {
      tail = math.max(tail, r.out[i].abs());
    }
    expect(tail, lessThan(0.01));
  });

  test('curve STOP is click-free across loop restarts and drives speed to 0', () {
    final e = make(5);
    e.curve.pts = Shapes.make(5, 2.0);
    e.curveEdited();
    var minSpeed = 9.0;
    final r = render(e, 1000, (_) => minSpeed = math.min(minSpeed, e.speedNow));
    expect(r.bad, false);
    expect(r.maxJump, lessThan(0.2));
    expect(minSpeed, lessThan(0.05));
  });

  test('curve REV settles at -1', () {
    final e = make(5);
    e.curve.pts = Shapes.make(7, 2.0);
    e.curveEdited();
    render(e, 100);
    expect((e.speedNow + 1.0).abs(), lessThan(0.02));
  });

  test('STOP spins the platter down, START brings it back', () {
    final e = make(5);
    render(e, 100);
    e.motorOn = false;
    render(e, 400);
    expect(e.speedNow.abs(), lessThan(0.02));
    e.motorOn = true;
    render(e, 400);
    expect((e.speedNow - 1.0).abs(), lessThan(0.02));
  });

  test('every pad shape is a valid curve and renders finite audio', () {
    for (final idx in Shapes.padShapes) {
      final pts = Shapes.make(idx, 2.0);
      for (var i = 1; i < pts.length; ++i) {
        expect(pts[i].x, greaterThan(pts[i - 1].x), reason: Shapes.names[idx]);
      }
      expect(pts.first.x, 0.0);
      expect(pts.last.x, closeTo(1.0, 1e-9));
      final e = make(5);
      e.curve.pts = pts;
      e.curveEdited();
      expect(render(e, 600).bad, false, reason: Shapes.names[idx]);
    }
  });

  test('the engine starts stopped and silent', () {
    final e = VinilEngine(sampleRate: sr)..setClip(tone(5));
    final r = render(e, 100);
    expect(e.motorOn, false);
    expect(r.out.every((v) => v.abs() < 1e-6), true);
  });

  test('curve serialisation round trip', () {
    final a = CurveModel()..pts = Shapes.make(8, 2.0);
    final b = CurveModel()..deserialize(a.serialize());
    expect(b.pts.length, a.pts.length);
  });

  test('no clip renders silence', () {
    final e = VinilEngine(sampleRate: sr);
    final r = render(e, 4);
    expect(r.out.every((v) => v == 0.0), true);
  });

  test('wav round trip', () {
    final src = tone(0.2);
    final back = Wav.decode(Wav.encode(src, sr), sr)!;
    expect(back.length, src.length);
    expect((back[1000] - src[1000]).abs(), lessThan(1e-3));
  });
}
