import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' hide IosAudioCategory;

import 'audio/wav.dart';
import 'dsp/engine.dart';

enum RecState { idle, recording }

/// Owns the engine, the audio output (the engine is pulled by the output) and the one stored recording.
class AppController extends ChangeNotifier {
  static const int sampleRate = 44100;
  static const int _chunk = 512; // frames per feed
  static const int _targetQueued =
      4096; // frames kept queued ahead of the output
  static const double _minClipSeconds = 0.3;

  final VinilEngine engine = VinilEngine(sampleRate: sampleRate);
  final AudioRecorder _recorder = AudioRecorder();

  RecState state = RecState.idle;
  double recordedSeconds = 0.0; // progress while recording
  String? message;

  /// peak of the clip per bin, for the waveform in the curve window
  final Float32List wave = Float32List(VinilEngine.waveBins);

  bool _outputOn = false;
  bool _disposed = false;
  Float32List? _rec;
  int _recCount = 0;
  int? _carry; // odd byte left over from a stream chunk
  StreamSubscription<Uint8List>? _sub;

  bool get recording => state == RecState.recording;
  bool get hasClip => engine.hasClip;

  /// length of the clip the curve is laid over
  /// while recording (and with no clip yet) the window shows the full 20 s; afterwards the clip is stretched over it
  double get clipSeconds => (engine.hasClip && !recording)
      ? engine.clipSeconds
      : VinilEngine.maxClipSeconds;

  Future<void> init() async {
    FlutterPcmSound.setLogLevel(LogLevel.error);
    await _loadSettings();
    try {
      final f = await _file();
      if (await f.exists()) {
        final clip = Wav.decode(await f.readAsBytes(), sampleRate);
        if (clip != null && clip.length > sampleRate * _minClipSeconds) {
          _setClip(
            clip.length > VinilEngine.maxClipSeconds * sampleRate
                ? Float32List.sublistView(
                    clip,
                    0,
                    (VinilEngine.maxClipSeconds * sampleRate).toInt(),
                  )
                : clip,
          );
        }
      }
    } catch (e) {
      debugPrint('could not load the last recording: $e');
    }
    await _startOutput();
    notifyListeners();
  }

  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}/last_recording.wav',
  );

  Float32List? _clip;

  void _setClip(Float32List clip) {
    _clip = clip;
    engine.setClip(clip);
    _rebuildWave(clip);
  }

  void _rebuildWave(Float32List clip) {
    wave.fillRange(0, wave.length, 0.0);
    for (var i = 0; i < clip.length; ++i) {
      final b = i * wave.length ~/ clip.length;
      final a = clip[i].abs();
      if (a > wave[b]) wave[b] = a;
    }
  }

  // ---- output --------------------------------------------------------------
  Future<void> _startOutput() async {
    if (_outputOn || !engine.hasClip || recording || _disposed) return;
    await FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: 2,
      iosAudioCategory: IosAudioCategory.playAndRecord,
    );
    await FlutterPcmSound.setFeedThreshold(_targetQueued ~/ 2);
    FlutterPcmSound.setFeedCallback(_onFeed);
    _outputOn = true;
    _onFeed(0);
  }

  Future<void> _stopOutput() async {
    if (!_outputOn) return;
    _outputOn = false;
    FlutterPcmSound.setFeedCallback(null);
    await FlutterPcmSound.release();
  }

  // ---- sliders (WEIGHT, DRAG, PREROLL), positions 0..1, kept between launches ----
  static const sliderDefaults = [0.4, 0.35, 0.0];
  final List<double> sliders = List.of(sliderDefaults);
  Timer? _saveTimer;

  void setSlider(int i, double v) {
    sliders[i] = v;
    _applySliders();
    notifyListeners();
    _saveSoon();
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveSettings);
  }

  // preroll runs 0..1000 ms with a 0.5 skew like the plugin
  void _applySliders() {
    engine.weight = sliders[0];
    engine.drag = sliders[1];
    engine.prerollMs = 1000.0 * sliders[2] * sliders[2];
  }

  Future<File> _settingsFile() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/settings.json');

  Future<void> _loadSettings() async {
    try {
      final f = await _settingsFile();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final v = (m['sliders'] as List).cast<num>();
        for (var i = 0; i < sliders.length && i < v.length; ++i) {
          sliders[i] = v[i].toDouble().clamp(0.0, 1.0);
        }
        final curve = m['curve'];
        if (curve is String)
          engine.curve.deserialize(
            curve,
          ); // falls back to flat when it is not valid
        engine.curveEdited();
      }
    } catch (e) {
      debugPrint('could not load settings: $e');
    }
    _applySliders();
  }

  /// also called when the app goes to the background, so nothing is lost when it is closed
  Future<void> saveSettings() async {
    _saveTimer?.cancel();
    try {
      await (await _settingsFile()).writeAsString(
        jsonEncode({'sliders': sliders, 'curve': engine.curve.serialize()}),
        flush: true,
      );
    } catch (e) {
      debugPrint('could not save settings: $e');
    }
  }

  final Float32List _mono = Float32List(_chunk);

  void _onFeed(int remaining) {
    if (!_outputOn) return;
    var queued = remaining;
    while (queued < _targetQueued) {
      engine.process(_mono, _chunk);
      final bytes = ByteData(_chunk * 4);
      for (var i = 0; i < _chunk; ++i) {
        final v = (_mono[i] * 32767.0).round().clamp(-32768, 32767);
        bytes.setInt16(i * 4, v, Endian.host);
        bytes.setInt16(i * 4 + 2, v, Endian.host);
      }
      FlutterPcmSound.feed(PcmArrayInt16(bytes: bytes));
      queued += _chunk;
    }
  }

  // ---- recording -----------------------------------------------------------
  Future<void> toggleRecording() async {
    if (recording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    if (recording) return;
    message = null;
    try {
      if (!await _recorder.hasPermission()) {
        message = 'MICROPHONE ACCESS DENIED';
        notifyListeners();
        return;
      }
      engine.grabbed = false;
      await _stopOutput();
      _rec = Float32List((VinilEngine.maxClipSeconds * sampleRate).toInt());
      _recCount = 0;
      _carry = null;
      recordedSeconds = 0.0;
      wave.fillRange(0, wave.length, 0.0);
      state = RecState.recording;
      notifyListeners();

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );
      _sub = stream.listen(
        _onBytes,
        onError: (Object e) {
          message = 'RECORDING FAILED';
          stopRecording();
        },
      );
    } catch (e) {
      debugPrint('start recording failed: $e');
      final old = _clip;
      if (old != null) _rebuildWave(old);
      message = 'RECORDING FAILED';
      state = RecState.idle;
      notifyListeners();
      await _startOutput();
    }
  }

  void _onBytes(Uint8List data) {
    final rec = _rec;
    if (rec == null || !recording) return;
    var i = 0;
    if (_carry != null && data.isNotEmpty) {
      _push(rec, _carry! | (data[0] << 8));
      _carry = null;
      i = 1;
    }
    for (; i + 1 < data.length && _recCount < rec.length; i += 2) {
      _push(rec, data[i] | (data[i + 1] << 8));
    }
    if (i < data.length && _recCount < rec.length) _carry = data[i];
    recordedSeconds = _recCount / sampleRate;
    notifyListeners();
    if (_recCount >= rec.length) stopRecording(); // max 20 s
  }

  void _push(Float32List rec, int u16) {
    if (_recCount >= rec.length) return;
    final s = u16 >= 0x8000 ? u16 - 0x10000 : u16;
    final a = s.abs() / 32768.0;
    final b =
        _recCount *
        wave.length ~/
        rec.length; // the window is the full 20 s while recording
    if (a > wave[b]) wave[b] = a;
    rec[_recCount++] = s / 32768.0;
  }

  Future<void> stopRecording() async {
    if (!recording) return;
    state = RecState.idle; // first, so late chunks are ignored
    engine.motorOn = true; // after a recording it always plays
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('stop recording failed: $e');
    }
    final rec = _rec;
    _rec = null;
    if (rec != null && _recCount >= sampleRate * _minClipSeconds) {
      final clip = Float32List.fromList(
        Float32List.sublistView(rec, 0, _recCount),
      ); // a new recording replaces the old one
      _setClip(clip);
      try {
        await (await _file()).writeAsBytes(
          Wav.encode(clip, sampleRate),
          flush: true,
        );
      } catch (e) {
        debugPrint('could not save the recording: $e');
      }
    } else {
      if (rec != null) message = 'TOO SHORT';
      final old = _clip;
      if (old != null) _rebuildWave(old); // keep the previous recording
    }
    notifyListeners();
    await _startOutput();
  }

  // ---- curve / parameters ---------------------------------------------------
  void curveEdited() {
    engine.curveEdited();
    notifyListeners();
    _saveSoon();
  }

  void setSmooth(bool v) {
    engine.smooth = v;
    curveEdited();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _recorder.dispose();
    _stopOutput();
    super.dispose();
  }
}
