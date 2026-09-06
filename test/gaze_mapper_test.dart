import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/gaze/gaze_mapper.dart';
import 'package:tcc_ela_eye_tracking_interface/models/gaze_command.dart';

void main() {
  math.Point<double> p(double x, double y) => math.Point(x, y);

  test('eyeFeature é invariante a escala e a translação', () {
    // O mesmo olhar, com o olho em tamanhos e posições diferentes no quadro.
    final small = eyeFeature(p(0, 0), p(10, 0), p(7, 1));
    final big = eyeFeature(p(0, 0), p(20, 0), p(14, 2));
    final moved = eyeFeature(p(100, 50), p(110, 50), p(107, 51));
    expect(big.x, closeTo(small.x, 1e-12));
    expect(big.y, closeTo(small.y, 1e-12));
    expect(moved.x, closeTo(small.x, 1e-12));
    expect(moved.y, closeTo(small.y, 1e-12));
  });

  test('recupera um polinômio conhecido', () {
    final truth = GazeMap(
      [0.5, 2.0, -0.3, 1.5, 0.4, -0.8],
      [0.4, 0.1, 2.2, -0.6, 1.1, 0.5],
    );
    final features = <math.Point<double>>[];
    for (var i = -2; i <= 2; i++) {
      for (var j = -2; j <= 2; j++) {
        features.add(p(i * 0.06, j * 0.06));
      }
    }
    final targets = features.map(truth.predict).toList();

    final fitted = fitGazeMap(features, targets, ridge: 0.0);
    for (var i = 0; i < 6; i++) {
      expect(fitted.coefX[i], closeTo(truth.coefX[i], 1e-6));
      expect(fitted.coefY[i], closeTo(truth.coefY[i], 1e-6));
    }
  });

  test('sobrevive ao JSON de ida e volta', () {
    final gm = GazeMap([1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1]);
    final back = GazeMap.fromJson(gm.toJson());
    expect(back.coefX, gm.coefX);
    expect(back.coefY, gm.coefY);
  });

  test('exige ao menos 6 alvos', () {
    final few = List.generate(5, (i) => p(i * 0.01, 0));
    expect(() => fitGazeMap(few, few), throwsArgumentError);
  });

  test('alvos degenerados não passam por singulares', () {
    // Nove alvos idênticos: o sistema não tem solução única.
    final same = List.generate(9, (_) => p(0.1, 0.1));
    expect(() => fitGazeMap(same, same, ridge: 0.0), throwsStateError);
  });

  test('9 alvos padrão ficam longe da borda', () {
    // A margem é 20%, não 12%: medindo no tablet, os alvos das quinas a 12%
    // saíram sistematicamente errados porque a essa excentricidade o usuário
    // vira a cabeça em vez de mover só os olhos.
    final targets = calibrationTargets();
    expect(targets.length, 9);
    expect(targets.first, p(0.20, 0.20));
    expect(targets.last.x, closeTo(0.80, 1e-12));
    expect(targets.last.y, closeTo(0.80, 1e-12));
    expect(targets[4], p(0.50, 0.50), reason: 'o alvo central tem de ser o centro');
  });

  test('zonas viram os comandos da interface', () {
    expect(commandFor(p(0.5, 0.5)), GazeCommand.select);
    expect(commandFor(p(0.02, 0.5)), GazeCommand.left);
    expect(commandFor(p(0.98, 0.5)), GazeCommand.right);
    expect(commandFor(p(0.5, 0.02)), GazeCommand.up);
    expect(commandFor(p(0.5, 0.98)), GazeCommand.down);
    // logo dentro do miolo, ainda é select
    expect(commandFor(p(0.20, 0.5)), GazeCommand.select);
  });

  _dadosReaisDoTablet();

  test('nas quinas ganha o lado mais extremo', () {
    // Fundo na faixa esquerda, raso na faixa de cima.
    expect(commandFor(p(0.01, 0.15)), GazeCommand.left);
    // Fundo na faixa de cima, raso na esquerda.
    expect(commandFor(p(0.13, 0.005)), GazeCommand.up);
  });
}

/// Calibração real medida no Galaxy Tab S9 FE (17:03 de 31/ago/2026).
/// Os alvos 3, 6 e 7 saíram errados: nas quinas o usuário virou a cabeça em vez
/// de mover só os olhos. Serve para travar o ganho do ajuste robusto.
void _dadosReaisDoTablet() {
  math.Point<double> p(double x, double y) => math.Point(x, y);

  final alvos = [
    p(0.12, 0.12), p(0.50, 0.12), p(0.88, 0.12),
    p(0.12, 0.50), p(0.50, 0.50), p(0.88, 0.50),
    p(0.12, 0.88), p(0.50, 0.88), p(0.88, 0.88),
  ];
  final v = [
    p(0.0478, -0.0804), p(-0.0044, -0.0798), p(-0.0171, -0.0797),
    p(0.0267, -0.0561), p(-0.0053, -0.0533), p(-0.0829, -0.0746),
    p(0.0247, -0.0475), p(-0.0472, 0.0311), p(-0.1109, 0.0431),
  ];

  double mediana(GazeMap m) {
    final e = <double>[];
    for (var i = 0; i < v.length; i++) {
      final q = m.predict(v[i]);
      e.add(math.sqrt(math.pow(q.x - alvos[i].x, 2) + math.pow(q.y - alvos[i].y, 2)));
    }
    e.sort();
    return e[e.length ~/ 2];
  }

  test('o ajuste robusto bate o simples nos dados reais', () {
    final simples = mediana(fitGazeMap(v, alvos));
    final robusto = fitGazeMapRobust(v, alvos);
    expect(simples, closeTo(0.154, 0.02), reason: 'resíduo do ajuste simples mudou');
    expect(robusto.residual, lessThan(simples),
        reason: 'descartar os alvos ruins tem de ajudar');
    expect(robusto.used, lessThan(v.length));
    expect(robusto.used, greaterThanOrEqualTo(7));
  });

  test('o sinal existe nos dois eixos', () {
    // Se isto falhar, o problema é a captura, não o ajuste.
    final xs = v.map((e) => e.x).toList()..sort();
    final ys = v.map((e) => e.y).toList()..sort();
    expect(xs.last - xs.first, greaterThan(0.09), reason: 'sem sinal horizontal');
    expect(ys.last - ys.first, greaterThan(0.09), reason: 'sem sinal vertical');
  });

  test('não descarta nada quando todos os alvos são bons', () {
    final limpos = alvos.map((t) => p((t.x - 0.5) * 0.2, (t.y - 0.5) * 0.2)).toList();
    final r = fitGazeMapRobust(limpos, alvos);
    expect(r.used, alvos.length);
    expect(r.residual, lessThan(0.01));
  });
}
