import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gaze/gaze_mapper.dart';
import '../gaze/gaze_tracker.dart';

/// Calibração em 9 alvos.
///
/// Sem ela o rastreador não funciona: o viés por pessoa responde por cerca de
/// 12% da energia do erro e não some por média temporal — medido no conjunto de
/// teste do detector. Sem calibrar, o erro estaciona em torno de 3,4°.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.tracker});

  final GazeTracker tracker;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _settle = Duration(milliseconds: 700);
  static const _collect = Duration(milliseconds: 1200);

  final _targets = calibrationTargets();
  final _features = <math.Point<double>>[];
  final _used = <math.Point<double>>[];
  final _samples = <math.Point<double>>[];

  late final _Poller _poller;
  int _index = 0;
  DateTime _started = DateTime.now();
  String? _error;

  /// Mapeamento usado só para desenhar a previsão enquanto calibra.
  ///
  /// Numa recalibração começa com o mapa atual; numa primeira calibração
  /// aparece assim que houver alvos suficientes para um ajuste, e vai
  /// melhorando a cada ponto.
  late GazeMap? _preview = widget.tracker.map;

  /// Últimas previsões, para o ponto não tremer a cada quadro.
  final _recent = <math.Point<double>>[];

  /// Evita contar o mesmo quadro várias vezes: o poller é mais rápido que a câmera.
  math.Point<double>? _lastAdded;

  @override
  void initState() {
    super.initState();
    // Construído aqui, não num `late final` com inicializador: `late` é
    // preguiçoso, e como nada lê o campo durante o build ele nunca chegaria a
    // existir — a tela ficava parada no primeiro alvo.
    _poller = _Poller(_onTick)..start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!mounted || _error != null) return;
    final elapsed = DateTime.now().difference(_started);

    final feature = widget.tracker.lastFeature;
    if (elapsed > _settle && feature != null && feature != _lastAdded) {
      _samples.add(feature);
      _lastAdded = feature;
    }

    final preview = _preview;
    if (feature != null && preview != null) {
      _recent.add(preview.predict(feature));
      if (_recent.length > 8) _recent.removeAt(0);
    }
    if (elapsed < _settle + _collect) {
      setState(() {});
      return;
    }

    // Mediana, não média: uma detecção ruim não deve arrastar o alvo inteiro.
    debugPrint('[gaze] alvo ${_index + 1}/${_targets.length}: '
        '${_samples.length} amostras');
    if (_samples.length >= 5) {
      _features.add(_medianOf(_samples));
      _used.add(_targets[_index]);
      // Reajusta a cada alvo novo: a previsão fica visível já no meio da
      // calibração, e melhora à medida que os pontos entram.
      if (_features.length >= 6) {
        try {
          _preview = fitGazeMapRobust(_features, _used).map;
        } on StateError {
          // alvos ainda degenerados; segue com a previsão anterior
        }
      }
    }
    _samples.clear();
    _index++;
    _started = DateTime.now();

    if (_index >= _targets.length) {
      _poller.stop();
      _finish();
      return;
    }
    setState(() {});
  }

  static math.Point<double> _medianOf(List<math.Point<double>> points) {
    final xs = points.map((p) => p.x).toList()..sort();
    final ys = points.map((p) => p.y).toList()..sort();
    final mid = xs.length ~/ 2;
    return math.Point(xs[mid], ys[mid]);
  }

  void _finish() {
    if (_features.length < 6) {
      setState(() => _error =
          'Só ${_features.length} de ${_targets.length} alvos foram medidos.\n'
          'Melhore a iluminação e mantenha o rosto no enquadramento.');
      return;
    }
    try {
      // Robusto: descarta os alvos que o usuário claramente não fixou. Nas
      // quinas isso é comum — a pessoa vira a cabeça em vez de mover os olhos.
      final result = fitGazeMapRobust(_features, _used);
      final map = result.map;
      final median = result.residual;

      final xs = _features.map((f) => f.x).toList()..sort();
      final ys = _features.map((f) => f.y).toList()..sort();
      debugPrint('[gaze] calibrado: ${result.used} de ${_features.length} alvos, '
          'resíduo mediano ${(median * 100).toStringAsFixed(1)}% da tela');
      debugPrint('[gaze] amplitude de v: '
          'x ${(xs.last - xs.first).toStringAsFixed(4)} '
          'y ${(ys.last - ys.first).toStringAsFixed(4)} '
          '(ruído esperado ~0.03)');
      for (var i = 0; i < _features.length; i++) {
        debugPrint('[gaze]   alvo (${_used[i].x.toStringAsFixed(2)},'
            '${_used[i].y.toStringAsFixed(2)}) -> v (${_features[i].x.toStringAsFixed(4)},'
            '${_features[i].y.toStringAsFixed(4)})');
      }
      if (!mounted) return;
      Navigator.of(context).pop((map: map, residual: median, targets: result.used));
    } on StateError catch (e) {
      setState(() => _error = 'Calibração degenerada: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
                const SizedBox(height: 16),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final elapsed = DateTime.now().difference(_started);
    final progress =
        ((elapsed - _settle).inMilliseconds / _collect.inMilliseconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final target = _targets[_index.clamp(0, _targets.length - 1)];
          return Stack(
            children: [
              Positioned(
                left: target.x * constraints.maxWidth - 40,
                top: target.y * constraints.maxHeight - 40,
                child: _CalibrationDot(progress: progress),
              ),
              if (_recent.isNotEmpty) _gazeDot(constraints),
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: Column(
                  children: [
                    Text(
                      progress == 0 ? 'Olhe para o ponto' : 'Medindo...',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_index + 1} de ${_targets.length}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Onde o rastreador acha que você está olhando, agora.
  ///
  /// Fica atrás do alvo e em outra cor para não competir com ele: o usuário tem
  /// de continuar olhando o alvo, não perseguir a própria previsão.
  Widget _gazeDot(BoxConstraints constraints) {
    final p = _medianOf(_recent);
    return Positioned(
      left: p.x.clamp(0.0, 1.0) * constraints.maxWidth - 14,
      top: p.y.clamp(0.0, 1.0) * constraints.maxHeight - 14,
      child: IgnorePointer(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.85), width: 2),
            color: Colors.cyanAccent.withValues(alpha: 0.15),
          ),
        ),
      ),
    );
  }


}
class _CalibrationDot extends StatelessWidget {
  const _CalibrationDot({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.amber),
            ),
          ),
          const CircleAvatar(radius: 8, backgroundColor: Colors.white),
        ],
      ),
    );
  }
}

/// Relógio mínimo: um AnimationController só para contar tempo seria peso morto.
class _Poller {
  _Poller(this.onTick);

  final void Function(Duration) onTick;
  bool _running = false;

  void start() {
    _running = true;
    _schedule();
  }

  void stop() => _running = false;

  void dispose() => _running = false;

  void _schedule() {
    if (!_running) return;
    Future<void>.delayed(const Duration(milliseconds: 33), () {
      if (!_running) return;
      onTick(Duration.zero);
      _schedule();
    });
  }
}
