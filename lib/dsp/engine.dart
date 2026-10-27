import 'dart:math' as math;
import 'dart:typed_data';

import 'curve.dart';

const double _twoPi = 2 * math.pi;

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// The scratch engine, a straight port of the VST processor. The recorded clip plays as the "live input"
/// (looping, so the loop restart lines up with the clip) and everything after that is the plugin's algorithm:
/// a circular buffer, a read head with a variable step, 4-point Hermite, cross-fade on every jump.
class VinilEngine {
  /// 33 1/3 rpm: one turn of the platter = 1.8 s of audio at speed 1
  static const double secondsPerRev = 1.8;
  static const int waveBins = 512;
  static const double maxClipSeconds = 20.0;
  static const double speedRange =
      2.0; // the curve goes from -2x (reverse) to +2x

  final int sampleRate;
  final CurveModel curve = CurveModel();

  // parameters (0..1, preroll in ms)
  double mix = 1.0, weight = 0.4, drag = 0.35, prerollMs = 0.0;
  bool smooth = true; // always on in the app
  bool motorOn = false; // the app starts stopped; START / STOP: off lets the platter spin down to a halt

  // clip
  Float32List? _clip;
  int _clipPos = 0;

  // ring buffer
  late final int _ringSize;
  late final Float32List _ring;
  int _writePos = 0;

  final Float32List _lut = Float32List(CurveModel.lutSize);

  // turntable input from the UI
  bool grabbed = false;
  bool scratching = false; // read by the UI: the record is being turned (or still catching up with the finger)
  double _pendingAngle = 0.0;

  // engine state
  final List<double> _heads = [0.0, 0.0]; // how far behind the live input the read head is (samples); [1] = outgoing head during a cross-fade
  double _fade = 1.0;
  bool _xfading = false;
  double _spd = 1.0;
  double _debt = 0.0;
  double _lastPhase = 0.0, _platterAng = 0.0;

  // read by the UI
  double cyclePhase = 0.0,
      playPhase = 0.0,
      speedNow = 1.0,
      platterAngle = 0.0,
      lagSeconds = 0.0;

  VinilEngine({this.sampleRate = 44100}) {
    _ringSize = ((maxClipSeconds + 10.0) * sampleRate).toInt() + 32;
    _ring = Float32List(_ringSize);
    curveEdited();
  }

  bool get hasClip => _clip != null;
  double get clipSeconds => _clip == null ? 0.0 : _clip!.length / sampleRate;

  void setClip(Float32List? clip) {
    _clip = (clip == null || clip.isEmpty) ? null : clip;
    reset();
  }

  void reset() {
    _ring.fillRange(0, _ringSize, 0.0);
    _writePos = 0;
    _clipPos = 0;
    _heads[0] = _heads[1] = 0.0;
    _fade = 1.0;
    _xfading = false;
    _spd = motorOn ? 1.0 : 0.0;
    _debt = 0.0;
    _lastPhase = 0.0;
    _pendingAngle = 0.0;
    cyclePhase = 0.0;
    playPhase = 0.0;
    speedNow = _spd;
    lagSeconds = 0.0;
  }

  /// bake after any change to [curve] or [smooth]
  void curveEdited() => curve.bake(_lut, CurveModel.lutSize, smooth);

  void addPlatterAngle(double radians) => _pendingAngle += radians;

  /// curve value (-1..1) at a loop phase 0..1
  double curveAt(double ph) =>
      _lut[(ph * (CurveModel.lutSize - 1)).toInt().clamp(
        0,
        CurveModel.lutSize - 1,
      )];

  // 4-point Hermite read from the circular buffer at a fractional position
  double _hermite(double pos) {
    final size = _ringSize;
    pos = pos % size;
    if (pos < 0.0) pos += size;
    var i1 = pos.floor();
    if (i1 >= size) i1 -= size;
    final f = pos - i1;
    final r = _ring;
    final i0 = i1 == 0 ? size - 1 : i1 - 1;
    var i2 = i1 + 1;
    if (i2 >= size) i2 -= size;
    var i3 = i1 + 2;
    if (i3 >= size) i3 -= size;
    final y0 = r[i0], y1 = r[i1], y2 = r[i2], y3 = r[i3];
    final c1 = 0.5 * (y2 - y0);
    final c2 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3;
    final c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2);
    return ((c3 * f + c2) * f + c1) * f + y1;
  }

  /// Renders [n] mono samples into [out].
  void process(Float32List out, int n) {
    final clip = _clip;
    if (clip == null) {
      out.fillRange(0, n, 0.0);
      return;
    }
    final fs = sampleRate.toDouble();
    final clipLen = clip.length;
    final prerollSamples = prerollMs * 0.001 * fs;

    // turntable input: the touch moves a target and the record follows it with a lag set by Weight
    _debt += _pendingAngle * secondsPerRev * fs / _twoPiD;
    _pendingAngle = 0.0;
    final isGrabbed = grabbed;

    final tauGrab = 0.003 + 0.05 * weight;
    final kGrab = 1.0 - math.exp(-1.0 / (tauGrab * fs));
    final tauCurve = 0.002 + 0.3 * drag * drag;
    final kCurve = 1.0 - math.exp(-1.0 / (tauCurve * fs));
    final xfadeInc = 1.0 / (0.006 * fs);
    final maxLag = _ringSize - 16.0;

    void jumpTo(double target) {
      if ((target - _heads[0]).abs() < 1.0) return;
      _heads[1] = _heads[0];
      _heads[0] = target;
      _fade = 0.0;
      _xfading = true;
    }

    var ph = _lastPhase;
    var following = false;
    for (var i = 0; i < n; ++i) {
      // loop clock: the clip is the loop
      ph = _clipPos / clipLen;
      final wrapped = ph < _lastPhase;
      _lastPhase = ph;

      _ring[_writePos] = clip[_clipPos];
      if (++_clipPos >= clipLen) _clipPos = 0;

      // ---- speed -------------------------------------------------------
      following = isGrabbed || _debt.abs() > 1.0;
      if (following) {
        final step = _debt * kGrab;
        _debt -= step;
        _spd = step;
      } else {
        // like a real record: let go and the platter returns to the speed of the curve (normal speed) and plays on from where it is
        final fp = ph * (CurveModel.lutSize - 1);
        final i0 = fp.toInt();
        final u =
            _lut[i0] +
            (_lut[math.min(i0 + 1, CurveModel.lutSize - 1)] - _lut[i0]) *
                (fp - i0);
        _spd += ((motorOn ? u * speedRange : 0.0) - _spd) * kCurve;
      }
      _spd = _clamp(_spd, -24.0, 24.0);

      // ---- loop restart: the curve starts over and the head is re-synced -----
      if (wrapped && !following) jumpTo(prerollSamples);

      // ---- move the heads (lag grows when slower than live, shrinks when faster) ----
      final heads = _xfading ? 2 : 1;
      for (var k = 0; k < heads; ++k) {
        _heads[k] = _clamp(_heads[k] + 1.0 - _spd, 0.0, maxLag);
      }

      // ---- read and mix ------------------------------------------------
      final holdGain = _clamp(
        _spd.abs() * 20.0,
        0.0,
        1.0,
      ); // a record that stands still: silence, not a DC step
      final dry = _ring[(_writePos - 2 + _ringSize) % _ringSize];
      var wet = _hermite(_writePos - _heads[0] - 2.0);
      if (_xfading) {
        wet =
            _hermite(_writePos - _heads[1] - 2.0) * (1.0 - _fade) + wet * _fade;
      }
      wet *= holdGain;
      out[i] = dry * (1.0 - mix) + wet * mix;
      if (_xfading) {
        _fade += xfadeInc;
        if (_fade >= 1.0) {
          _fade = 1.0;
          _xfading = false;
        }
      }

      _platterAng += _spd * _twoPiD / (secondsPerRev * fs);
      if (++_writePos >= _ringSize) _writePos = 0;
    }

    _platterAng = _platterAng % _twoPiD;
    if (_platterAng < 0.0) _platterAng += _twoPiD;

    cyclePhase = ph;
    // where in the recording the sound comes from: the loop clock minus how far the read head lags behind it
    playPhase = (ph - _heads[0] / clipLen) % 1.0;
    if (playPhase < 0.0) playPhase += 1.0;
    scratching = following;
    speedNow = _spd;
    platterAngle = _platterAng;
    lagSeconds = _heads[0] / fs;
  }

  static const double _twoPiD = _twoPi;
}
