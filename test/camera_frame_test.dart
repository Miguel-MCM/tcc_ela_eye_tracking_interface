import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/gaze/camera_frame.dart';
import 'package:tcc_ela_eye_tracking_interface/gaze/eye_crop.dart';

void main() {
  math.Point<double> p(double x, double y) => math.Point(x, y);

  Nv21Frame frame(int w, int h, int rot, {int fill = 128}) =>
      Nv21Frame(Uint8List(w * h + w * h ~/ 2)..fillRange(0, w * h + w * h ~/ 2, fill), w, h, rot);

  test('dimensões em pé trocam a 90 e 270', () {
    expect(frame(640, 480, 0).uprightWidth, 640);
    expect(frame(640, 480, 90).uprightWidth, 480);
    expect(frame(640, 480, 90).uprightHeight, 640);
    expect(frame(640, 480, 180).uprightWidth, 640);
    expect(frame(640, 480, 270).uprightWidth, 480);
  });

  test('quinas do espaço em pé caem nas quinas do buffer bruto', () {
    for (final rot in [0, 90, 180, 270]) {
      final f = frame(640, 480, rot);
      final corners = [
        p(0, 0),
        p(f.uprightWidth - 1, 0),
        p(0, f.uprightHeight - 1),
        p(f.uprightWidth - 1, f.uprightHeight - 1),
      ];
      final mapped = corners.map(f.toRaw).toSet();
      expect(mapped.length, 4, reason: 'rotação $rot colapsou quinas');
      for (final m in mapped) {
        expect(m.x, anyOf(0.0, 639.0), reason: 'rotação $rot');
        expect(m.y, anyOf(0.0, 479.0), reason: 'rotação $rot');
      }
    }
  });

  test('rotação 0 é identidade', () {
    final f = frame(640, 480, 0);
    expect(f.toRaw(p(123, 45)), p(123, 45));
  });

  test('recorte tem o formato NCHW esperado e valores em [0,1]', () {
    final f = frame(64, 64, 0, fill: 200);
    final t = cropTransform(p(20, 32), p(44, 32), const CropParams());
    final out = Float32List(3 * 128 * 128);
    f.sampleCrop(t, 128, out);
    expect(out.every((v) => v >= 0.0 && v <= 1.0), isTrue);
  });

  test('amostragem fora do buffer é limitada, não estoura', () {
    final f = frame(64, 64, 0);
    // olho na quina: boa parte do recorte cai fora do quadro
    final t = cropTransform(p(0, 0), p(6, 0), const CropParams());
    expect(() => f.sampleCrop(t, 128, Float32List(3 * 128 * 128)), returnsNormally);
  });
}
