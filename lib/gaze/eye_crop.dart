import 'dart:math' as math;
import 'dart:typed_data';

/// Geometria do recorte de olho.
///
/// Porte fiel de `src/eyetracker/eye_crop.py` do projeto de treino. Se esta
/// transformação divergir da usada no treino, o modelo passa a ver um domínio
/// diferente e erra sem dar sinal — por isso `test/eye_crop_test.dart` trava os
/// números contra os valores gerados pela versão Python.
class CropParams {
  const CropParams({
    this.cropRatio = 1.6,
    this.cropSize = 128,
    this.pupilBoxRatio = 0.20,
    this.alignRoll = true,
  });

  /// Lado do recorte, em múltiplos da largura do olho.
  final double cropRatio;

  /// Resolução final do recorte, em px.
  final int cropSize;

  /// Lado da caixa da pupila, em múltiplos da largura do olho.
  final double pupilBoxRatio;

  /// Rotaciona para deixar os cantos do olho horizontais.
  final bool alignRoll;

  factory CropParams.fromJson(Map<String, dynamic> json) => CropParams(
        cropRatio: (json['crop_ratio'] as num).toDouble(),
        cropSize: (json['crop_size'] as num).toInt(),
        pupilBoxRatio: (json['pupil_box_ratio'] as num).toDouble(),
        alignRoll: json['align_roll'] as bool,
      );
}

/// Transformação afim entre o quadro da câmera e o recorte.
class CropTransform {
  CropTransform._(this.matrix, this.inverse, this.eyeWidth, this.angleDeg, this.scale);

  /// Quadro -> recorte, na ordem [a, b, c, d, e, f].
  final Float64List matrix;

  /// Recorte -> quadro.
  final Float64List inverse;

  final double eyeWidth;
  final double angleDeg;
  final double scale;

  static math.Point<double> _apply(Float64List m, math.Point<double> p) =>
      math.Point(m[0] * p.x + m[1] * p.y + m[2], m[3] * p.x + m[4] * p.y + m[5]);

  math.Point<double> toCrop(math.Point<double> p) => _apply(matrix, p);

  math.Point<double> toFrame(math.Point<double> p) => _apply(inverse, p);
}

/// Monta a afim a partir dos dois cantos do olho.
///
/// Replica `cv2.getRotationMatrix2D(centro, ângulo, escala)`, cuja parte linear
/// é `escala * [[cos, sen], [-sen, cos]]`. Aplicada ao vetor do olho, o
/// resultado fica horizontal exatamente quando o ângulo é `atan2(dy, dx)`.
CropTransform cropTransform(
  math.Point<double> cornerA,
  math.Point<double> cornerB,
  CropParams params,
) {
  final cx = (cornerA.x + cornerB.x) / 2.0;
  final cy = (cornerA.y + cornerB.y) / 2.0;
  final dx = cornerB.x - cornerA.x;
  final dy = cornerB.y - cornerA.y;
  final eyeWidth = math.sqrt(dx * dx + dy * dy);
  if (eyeWidth <= 1e-6) {
    throw ArgumentError('cantos do olho coincidentes: largura nula');
  }

  final scale = params.cropSize / (params.cropRatio * eyeWidth);
  final angle = params.alignRoll ? math.atan2(dy, dx) : 0.0;
  final alpha = scale * math.cos(angle);
  final beta = scale * math.sin(angle);

  final half = params.cropSize / 2.0;
  // getRotationMatrix2D mantém o centro fixo; o deslocamento leva o centro do
  // olho para o centro do recorte.
  final m = Float64List.fromList([
    alpha, beta, (1 - alpha) * cx - beta * cy + half - cx,
    -beta, alpha, beta * cx + (1 - alpha) * cy + half - cy,
  ]);

  final det = m[0] * m[4] - m[1] * m[3];
  final inv = Float64List.fromList([
    m[4] / det, -m[1] / det, (m[1] * m[5] - m[4] * m[2]) / det,
    -m[3] / det, m[0] / det, (m[3] * m[2] - m[0] * m[5]) / det,
  ]);

  return CropTransform._(m, inv, eyeWidth, angle * 180.0 / math.pi, scale);
}
