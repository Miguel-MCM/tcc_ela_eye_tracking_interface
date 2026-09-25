import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/gaze/gaze_tracker.dart';

CameraDescription cam(int sensor, CameraLensDirection dir) =>
    CameraDescription(name: 'c', lensDirection: dir, sensorOrientation: sensor);

void main() {
  test('frontal soma a rotação da tela; traseira subtrai', () {
    final front = cam(270, CameraLensDirection.front);
    final back = cam(90, CameraLensDirection.back);
    // aparelho na vertical: só o sensor conta
    expect(rotationDegreesFor(front, DeviceOrientation.portraitUp), 270);
    expect(rotationDegreesFor(back, DeviceOrientation.portraitUp), 90);
    // paisagem: é o caso do tablet, e o que estava faltando
    expect(rotationDegreesFor(front, DeviceOrientation.landscapeLeft), 0);
    expect(rotationDegreesFor(back, DeviceOrientation.landscapeLeft), 0);
    expect(rotationDegreesFor(front, DeviceOrientation.landscapeRight), 180);
  });

  test('resultado é sempre um múltiplo de 90 válido para o ML Kit', () {
    for (final sensor in [0, 90, 180, 270]) {
      for (final dir in CameraLensDirection.values) {
        for (final o in DeviceOrientation.values) {
          final r = rotationDegreesFor(cam(sensor, dir), o);
          expect([0, 90, 180, 270], contains(r));
        }
      }
    }
  });
}
