import 'dart:math' as math;
import 'dart:typed_data';

import 'eye_crop.dart';

/// Amostragem de recortes de olho direto do buffer NV21 da câmera.
///
/// Converter o quadro inteiro para RGB custaria ~900 mil pixels; o modelo só
/// precisa de 128×128 por olho. Amostrar pela afim inversa faz ~33 mil leituras
/// por quadro e dispensa qualquer buffer intermediário.
class Nv21Frame {
  const Nv21Frame(this.bytes, this.width, this.height, this.rotationDegrees);

  final Uint8List bytes;

  /// Dimensões do buffer **bruto**, antes da rotação de tela.
  final int width;
  final int height;

  /// Rotação que leva o buffer bruto ao espaço em pé (0, 90, 180 ou 270).
  final int rotationDegrees;

  /// Dimensões no espaço em pé — o mesmo que o ML Kit usa para os landmarks.
  int get uprightWidth => rotationDegrees % 180 == 0 ? width : height;
  int get uprightHeight => rotationDegrees % 180 == 0 ? height : width;

  /// Leva um ponto do espaço em pé (ML Kit) para o buffer bruto.
  ///
  /// É a inversa da rotação que o ML Kit aplica internamente. Sem isto os
  /// landmarks e a amostragem viveriam em espaços diferentes, e o recorte
  /// sairia deslocado ou girado sem nenhum erro visível.
  math.Point<double> toRaw(math.Point<double> upright) {
    switch (rotationDegrees % 360) {
      case 90:
        return math.Point(upright.y, height - 1 - upright.x);
      case 180:
        return math.Point(width - 1 - upright.x, height - 1 - upright.y);
      case 270:
        return math.Point(width - 1 - upright.y, upright.x);
      default:
        return upright;
    }
  }

  int _clamp(int v, int hi) => v < 0 ? 0 : (v > hi ? hi : v);

  /// Recorta o olho escrevendo a entrada do modelo em [out]: NCHW, RGB, [0,1].
  ///
  /// [out] é o buffer nativo do tensor de entrada, preenchido no lugar: copiar
  /// 196 KB por olho por quadro custava mais que a própria inferência.
  ///
  /// [transform] tem de estar no espaço **bruto** — use [toRaw] nos cantos
  /// antes de montá-la.
  void sampleCrop(CropTransform transform, int size, Float32List out) {
    final plane = size * size;
    final inv = transform.inverse;
    final uvOffset = width * height;

    for (var dy = 0; dy < size; dy++) {
      final dyd = dy + 0.5;
      for (var dx = 0; dx < size; dx++) {
        final dxd = dx + 0.5;
        // Vizinho mais próximo: a 128 px o custo de interpolar não se paga, e o
        // treino também viu recortes reamostrados.
        final sx = _clamp((inv[0] * dxd + inv[1] * dyd + inv[2]).round(), width - 1);
        final sy = _clamp((inv[3] * dxd + inv[4] * dyd + inv[5]).round(), height - 1);

        final y = bytes[sy * width + sx].toDouble();
        final uvIndex = uvOffset + (sy >> 1) * width + (sx & ~1);
        final v = bytes[uvIndex].toDouble() - 128.0;
        final u = bytes[uvIndex + 1].toDouble() - 128.0;

        final r = (y + 1.370705 * v).clamp(0.0, 255.0) / 255.0;
        final g = (y - 0.337633 * u - 0.698001 * v).clamp(0.0, 255.0) / 255.0;
        final b = (y + 1.732446 * u).clamp(0.0, 255.0) / 255.0;

        final i = dy * size + dx;
        out[i] = r;
        out[plane + i] = g;
        out[2 * plane + i] = b;
      }
    }
  }
}
