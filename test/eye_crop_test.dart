import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/gaze/eye_crop.dart';

/// Valores gerados pela implementação Python usada no treino
/// (`src/eyetracker/eye_crop.py` + `cv2.invertAffineTransform`).
/// Se este teste falhar, o app passou a recortar diferente do treino.
void main() {
  const params = CropParams();
  math.Point<double> p(double x, double y) => math.Point(x, y);

  test('afim bate com a referência Python (olho quase horizontal)', () {
    final t = cropTransform(p(614, 355), p(684, 357), params);
    expect(t.eyeWidth, closeTo(70.028566, 1e-6));
    expect(t.angleDeg, closeTo(1.636577, 1e-6));
    expect(t.matrix, [
      closeTo(1.1419249592, 1e-9), closeTo(0.0326264274, 1e-9), closeTo(-688.7243066884, 1e-6),
      closeTo(-0.0326264274, 1e-9), closeTo(1.1419249592, 1e-9), closeTo(-321.3507340946, 1e-6),
    ]);
    expect(t.inverse, [
      closeTo(0.875, 1e-9), closeTo(-0.025, 1e-9), closeTo(594.6, 1e-6),
      closeTo(0.025, 1e-9), closeTo(0.875, 1e-9), closeTo(298.4, 1e-6),
    ]);
  });

  test('centro do recorte volta ao centro entre os cantos', () {
    final t = cropTransform(p(614, 355), p(684, 357), params);
    final back = t.toFrame(p(64, 64));
    expect(back.x, closeTo(649.0, 1e-6));
    expect(back.y, closeTo(356.0, 1e-6));
  });

  test('pupila do recorte volta ao quadro (olho inclinado)', () {
    final t = cropTransform(p(769, 368), p(842, 379), params);
    expect(t.angleDeg, closeTo(8.569142, 1e-6));
    final back = t.toFrame(p(53.7, 64.3));
    expect(back.x, closeTo(796.060, 1e-3));
    expect(back.y, closeTo(372.3575, 1e-3));
  });

  test('caso degenerado: olho vertical', () {
    final t = cropTransform(p(100, 300), p(100, 200), params);
    expect(t.angleDeg, closeTo(-90.0, 1e-6));
    final back = t.toFrame(p(53.7, 64.3));
    expect(back.x, closeTo(100.375, 1e-6));
    expect(back.y, closeTo(262.875, 1e-6));
  });

  test('cantos alinham na horizontal dentro do recorte', () {
    final t = cropTransform(p(769, 368), p(842, 379), params);
    final a = t.toCrop(p(769, 368));
    final b = t.toCrop(p(842, 379));
    expect(a.y, closeTo(b.y, 1e-9));
    // largura projetada = cropSize / cropRatio, independente do olho
    expect(b.x - a.x, closeTo(128 / 1.6, 1e-9));
  });

  test('cantos coincidentes são rejeitados', () {
    expect(() => cropTransform(p(10, 10), p(10, 10), params), throwsArgumentError);
  });
}
