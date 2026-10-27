import 'dart:typed_data';

/// Mono 16-bit PCM WAV, the format the last recording is stored in.
class Wav {
  static Uint8List encode(Float32List samples, int sampleRate) {
    final dataLen = samples.length * 2;
    final b = ByteData(44 + dataLen);
    void tag(int o, String s) {
      for (var i = 0; i < 4; ++i) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; ++i) {
      final v = (samples[i] * 32767.0).round().clamp(-32768, 32767);
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// Returns null when the bytes are not a WAV written by [encode] at [sampleRate].
  static Float32List? decode(Uint8List bytes, int sampleRate) {
    if (bytes.length < 44) return null;
    final b = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(36, 40)) != 'data') {
      return null;
    }
    if (b.getUint32(24, Endian.little) != sampleRate ||
        b.getUint16(22, Endian.little) != 1) {
      return null;
    }
    final n = (bytes.length - 44) ~/ 2;
    final out = Float32List(n);
    for (var i = 0; i < n; ++i) {
      out[i] = b.getInt16(44 + i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
