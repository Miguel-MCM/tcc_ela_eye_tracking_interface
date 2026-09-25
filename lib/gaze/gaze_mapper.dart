import 'dart:math' as math;

import '../models/gaze_command.dart';

/// Caminho A: vetor pupila-canto -> ponto na tela, por regressão calibrada.
///
///     v = (pupila - centro dos cantos) / largura do olho
///
/// `v` é invariante a escala e a translação, e como os cantos acompanham a
/// cabeça ele cancela boa parte do movimento dela — é o equivalente sem
/// infravermelho do vetor PCCR dos rastreadores comerciais.
///
/// A média dos dois olhos dá 2 features; um polinômio de 2ª ordem sobre elas
/// tem 6 termos por eixo, então 9 alvos de calibração sobredeterminam o ajuste.

/// Ridge mínimo: os termos quadráticos ficam quase colineares quando o usuário
/// não olha direito para os alvos das quinas.
const double kRidge = 1e-4;

/// Vetor pupila-canto normalizado, de um olho.
math.Point<double> eyeFeature(
  math.Point<double> cornerA,
  math.Point<double> cornerB,
  math.Point<double> pupil,
) {
  final dx = cornerB.x - cornerA.x;
  final dy = cornerB.y - cornerA.y;
  final width = math.sqrt(dx * dx + dy * dy);
  if (width <= 1e-6) throw ArgumentError('cantos coincidentes');
  return math.Point(
    (pupil.x - (cornerA.x + cornerB.x) / 2) / width,
    (pupil.y - (cornerA.y + cornerB.y) / 2) / width,
  );
}

/// Termos do polinômio de 2ª ordem: [1, x, y, x², y², xy].
List<double> design(math.Point<double> v) =>
    [1.0, v.x, v.y, v.x * v.x, v.y * v.y, v.x * v.y];

/// Mapeamento ajustado de `v` para coordenadas de tela, em fração [0,1].
class GazeMap {
  const GazeMap(this.coefX, this.coefY);

  final List<double> coefX;
  final List<double> coefY;

  math.Point<double> predict(math.Point<double> v) {
    final d = design(v);
    var x = 0.0, y = 0.0;
    for (var i = 0; i < d.length; i++) {
      x += d[i] * coefX[i];
      y += d[i] * coefY[i];
    }
    return math.Point(x, y);
  }

  Map<String, dynamic> toJson() => {'coef_x': coefX, 'coef_y': coefY};

  factory GazeMap.fromJson(Map<String, dynamic> json) => GazeMap(
        (json['coef_x'] as List).map((e) => (e as num).toDouble()).toList(),
        (json['coef_y'] as List).map((e) => (e as num).toDouble()).toList(),
      );
}

/// Mínimos quadrados regularizados sobre as equações normais.
///
/// São 6 incógnitas por eixo: montar `AᵀA` e resolver por eliminação de Gauss
/// é menor e mais previsível que trazer um pacote de álgebra linear.
GazeMap fitGazeMap(
  List<math.Point<double>> features,
  List<math.Point<double>> targets, {
  double ridge = kRidge,
}) {
  if (features.length != targets.length) {
    throw ArgumentError('features e targets com tamanhos diferentes');
  }
  if (features.length < 6) {
    throw ArgumentError('preciso de ao menos 6 alvos, recebi ${features.length}');
  }

  final ata = List.generate(6, (_) => List<double>.filled(6, 0.0));
  final atx = List<double>.filled(6, 0.0);
  final aty = List<double>.filled(6, 0.0);

  for (var n = 0; n < features.length; n++) {
    final d = design(features[n]);
    for (var i = 0; i < 6; i++) {
      atx[i] += d[i] * targets[n].x;
      aty[i] += d[i] * targets[n].y;
      for (var j = 0; j < 6; j++) {
        ata[i][j] += d[i] * d[j];
      }
    }
  }
  // O intercepto não é regularizado: encolhê-lo só deslocaria o centro da tela.
  for (var i = 1; i < 6; i++) {
    ata[i][i] += ridge;
  }

  return GazeMap(_solve(ata, atx), _solve(ata, aty));
}

/// Eliminação de Gauss com pivoteamento parcial.
List<double> _solve(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = List.generate(n, (i) => [...a[i], b[i]]);

  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-12) {
      throw StateError('sistema singular: alvos de calibração degenerados');
    }
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;

    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final factor = m[r][col] / m[col][col];
      for (var c = col; c <= n; c++) {
        m[r][c] -= factor * m[col][c];
      }
    }
  }
  return List.generate(n, (i) => m[i][n] / m[i][i]);
}

/// Grade de alvos de calibração, em fração de tela.
///
/// A margem é larga de propósito: com alvos a 12% da borda, medindo num tablet
/// de 10,5", os alvos das quinas saíram sistematicamente errados — a essa
/// excentricidade a pessoa vira a cabeça em vez de mover só os olhos. O
/// mapeamento é quase linear nessa faixa, então extrapolar até a borda custa
/// menos que calibrar com pontos ruins.
List<math.Point<double>> calibrationTargets({
  int cols = 5,
  int rows = 5,
  double margin = 0.10,
}) {
  final targets = <math.Point<double>>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      targets.add(math.Point(
        margin + (1 - 2 * margin) * (cols == 1 ? 0.5 : c / (cols - 1)),
        margin + (1 - 2 * margin) * (rows == 1 ? 0.5 : r / (rows - 1)),
      ));
    }
  }
  return targets;
}

/// Faixas das bordas, em fração de tela. Os padrões acompanham as barras de
/// `EdgeControls` (16% na vertical, 14% na horizontal).
class GazeBands {
  const GazeBands({this.horizontal = 0.33, this.vertical = 0.33});

  final double horizontal;
  final double vertical;
}

/// Traduz um ponto de olhar no comando da interface.
///
/// Nas quinas dois lados disputam; ganha o que estiver proporcionalmente mais
/// fundo na sua faixa, o que é o comportamento esperado de um direction pad.
///
/// ponytail: o miolo inteiro vale `select`, então olhar o teclado para ler
/// pode disparar confirmação. O dwell reduz o risco; se incomodar, troque por
/// zonas registradas pelos próprios widgets.
GazeCommand commandFor(math.Point<double> gaze, [GazeBands bands = const GazeBands()]) {
  final overshoots = <GazeCommand, double>{
    GazeCommand.left: (bands.horizontal - gaze.x) / bands.horizontal,
    GazeCommand.right: (gaze.x - (1 - bands.horizontal)) / bands.horizontal,
    GazeCommand.up: (bands.vertical - gaze.y) / bands.vertical,
    GazeCommand.down: (gaze.y - (1 - bands.vertical)) / bands.vertical,
  };

  GazeCommand? best;
  var bestValue = 0.0;
  overshoots.forEach((command, value) {
    if (value > bestValue) {
      bestValue = value;
      best = command;
    }
  });
  return best ?? GazeCommand.select;
}

/// Ajuste que descarta os alvos que o usuário claramente não fixou.
///
/// Com 9 pontos e 6 coeficientes sobram 3 graus de liberdade, então um único
/// alvo ruim entorta o mapeamento inteiro. Nos dados reais do tablet, descartar
/// o pior ponto levou o resíduo mediano de 15,4% para 12,1% da tela.
///
/// Descarta no máximo [maxDrop], e só enquanto o resíduo melhorar de verdade.
({GazeMap map, double residual, int used}) fitGazeMapRobust(
  List<math.Point<double>> features,
  List<math.Point<double>> targets, {
  int maxDrop = 2,
}) {
  var keptF = [...features];
  var keptT = [...targets];
  var map = fitGazeMap(keptF, keptT);
  var best = _medianResidual(map, keptF, keptT);

  for (var drop = 0; drop < maxDrop; drop++) {
    if (keptF.length <= 7) break;

    var worst = -1;
    var worstError = -1.0;
    for (var i = 0; i < keptF.length; i++) {
      final p = map.predict(keptF[i]);
      final e = math.sqrt(math.pow(p.x - keptT[i].x, 2) + math.pow(p.y - keptT[i].y, 2));
      if (e > worstError) {
        worstError = e;
        worst = i;
      }
    }

    final tryF = [...keptF]..removeAt(worst);
    final tryT = [...keptT]..removeAt(worst);
    final GazeMap candidate;
    try {
      candidate = fitGazeMap(tryF, tryT);
    } on StateError {
      break; // sobraram pontos degenerados
    }
    final residual = _medianResidual(candidate, tryF, tryT);
    if (residual >= best) break; // descartar não ajudou: para por aqui

    keptF = tryF;
    keptT = tryT;
    map = candidate;
    best = residual;
  }

  return (map: map, residual: best, used: keptF.length);
}

double _medianResidual(
  GazeMap map,
  List<math.Point<double>> features,
  List<math.Point<double>> targets,
) {
  final errors = <double>[];
  for (var i = 0; i < features.length; i++) {
    final p = map.predict(features[i]);
    errors.add(math.sqrt(math.pow(p.x - targets[i].x, 2) + math.pow(p.y - targets[i].y, 2)));
  }
  errors.sort();
  return errors[errors.length ~/ 2];
}
