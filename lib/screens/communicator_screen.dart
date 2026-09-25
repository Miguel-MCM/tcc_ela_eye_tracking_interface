import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gaze/gaze_mapper.dart';
import '../gaze/gaze_tracker.dart';
import '../gaze/pupil_detector.dart';
import '../models/control_style.dart';
import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';
import '../models/word_predictor.dart';
import '../widgets/camera_view.dart';
import '../widgets/direction_pad.dart';
import '../widgets/edge_controls.dart';
import '../widgets/gaze_button.dart';
import '../widgets/message_bar.dart';
import '../widgets/on_screen_keyboard.dart';
import 'calibration_screen.dart';

/// Tela principal: prévia da câmera, setas de navegação e teclado.
///
/// Toda a interação passa por [_handleCommand]. Quando o eye tracking entrar,
/// basta ele chamar esse mesmo método — nada aqui precisa mudar.
class CommunicatorScreen extends StatefulWidget {
  const CommunicatorScreen({super.key, this.controlStyle = ControlStyle.edges});

  final ControlStyle controlStyle;

  @override
  State<CommunicatorScreen> createState() => _CommunicatorScreenState();
}

/// Largura/altura do teclado que deixa as teclas aproximadamente quadradas,
/// derivada do próprio layout em vez de um número mágico.
final double _keyboardAspectRatio =
    kKeyboardRows.map((row) => row.length).reduce((a, b) => a > b ? a : b) /
    (kKeyboardRows.length + 0.4);

/// Em retrato o miolo é estreito e alto: teclas quadradas deixariam o teclado
/// minúsculo no meio de um vazio. Esticá-las na vertical aproveita a altura
/// disponível sem espremer a largura, que é o eixo escasso.
final double _keyboardAspectRatioTall = _keyboardAspectRatio / 1.4;

class _CommunicatorScreenState extends State<CommunicatorScreen> {
  final _wordPredictor = WordPredictor.defaultModel();
  String _message = '';
  int _row = 0;
  int _column = 0;
  int? _selectedSuggestion;

  List<String> get _suggestions => _wordPredictor.suggest(_message);

  GazeTracker? _tracker;
  StreamSubscription<GazeCommand>? _commandSub;
  StreamSubscription<GazeSample>? _sampleSub;
  GazeSample? _gaze;
  String? _gazeError;

  @override
  void dispose() {
    _commandSub?.cancel();
    _sampleSub?.cancel();
    _tracker?.dispose();
    super.dispose();
  }

  /// A câmera fica pronta depois da tela; o rastreador só pode ser ligado aqui.
  Future<void> _onCameraReady(CameraController? controller) async {
    if (controller == null) {
      await _commandSub?.cancel();
      await _sampleSub?.cancel();
      await _tracker?.dispose();
      if (mounted) setState(() => _tracker = null);
      return;
    }
    if (_tracker != null) return;

    try {
      final tracker = GazeTracker(
        detector: await PupilDetector.load(),
        cropParams: await GazeTracker.loadCropParams(),
      );
      // O rastreador emite exatamente os mesmos comandos das setas, então entra
      // por _handleCommand sem que nada na interface precise mudar.
      _commandSub = tracker.commands.listen(_handleCommand);
      _sampleSub = tracker.samples.listen((s) {
        if (mounted) setState(() => _gaze = s);
      });
      await tracker.attach(controller);
      if (!mounted) {
        await tracker.dispose();
        return;
      }
      setState(() => _tracker = tracker);
    } catch (e, stack) {
      // Sem este log a falha só apareceria como um ícone, e a causa se perderia.
      debugPrint('[gaze] falha ao iniciar o rastreador: $e\n$stack');
      if (mounted) setState(() => _gazeError = '$e');
    }
  }

  Future<void> _calibrate() async {
    final tracker = _tracker;
    if (tracker == null) return;
    final result = await Navigator.of(context)
        .push<({GazeMap map, double residual, int targets})>(
          MaterialPageRoute(
            builder: (_) => CalibrationScreen(tracker: tracker),
          ),
        );
    if (result == null || !mounted) return;
    setState(() => tracker.map = result.map);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Calibrado com ${result.targets} alvos · resíduo '
          '${(result.residual * 100).toStringAsFixed(1)}% da tela',
        ),
      ),
    );
  }

  void _handleCommand(GazeCommand command) {
    switch (command) {
      case GazeCommand.up:
        _moveRow(-1);
      case GazeCommand.down:
        _moveRow(1);
      case GazeCommand.left:
        _moveColumn(-1);
      case GazeCommand.right:
        _moveColumn(1);
      case GazeCommand.select:
        final suggestionIndex = _selectedSuggestion;
        if (suggestionIndex != null) {
          _acceptSuggestion(_suggestions[suggestionIndex]);
        } else {
          _pressKey(_row, _column);
        }
    }
  }

  void _moveRow(int delta) {
    if (_selectedSuggestion != null) {
      if (delta > 0) {
        setState(() => _selectedSuggestion = null);
      }
      return;
    }

    if (delta < 0 &&
        _row == 0 &&
        _message.isNotEmpty &&
        _suggestions.isNotEmpty) {
      setState(() => _selectedSuggestion = 0);
      return;
    }

    final row = (_row + delta).clamp(0, kKeyboardRows.length - 1);
    setState(() {
      _row = row;
      // As linhas têm tamanhos diferentes: ao mudar de linha a coluna pode
      // ficar fora do intervalo.
      _column = _column.clamp(0, kKeyboardRows[row].length - 1);
    });
  }

  void _moveColumn(int delta) {
    final suggestionIndex = _selectedSuggestion;
    if (suggestionIndex != null) {
      setState(() {
        _selectedSuggestion = (suggestionIndex + delta).clamp(
          0,
          _suggestions.length - 1,
        );
      });
      return;
    }

    setState(() {
      _column = (_column + delta).clamp(0, kKeyboardRows[_row].length - 1);
    });
  }

  void _pressKey(int row, int column) {
    final keyDef = kKeyboardRows[row][column];
    setState(() {
      _row = row;
      _column = column;
      _selectedSuggestion = null;
      switch (keyDef.action) {
        case KeyAction.character:
          _message += keyDef.label;
        case KeyAction.space:
          if (_message.isNotEmpty && !_message.endsWith(' ')) _message += ' ';
        case KeyAction.backspace:
          if (_message.isNotEmpty) {
            _message = _message.substring(0, _message.length - 1);
          }
        case KeyAction.clear:
          _message = '';
      }
    });
  }

  void _acceptSuggestion(String suggestion) {
    final endsWithSpace = _message.endsWith(' ');
    final completesCurrentWord = _wordPredictor
        .suggest('$_message ')
        .contains(suggestion);
    final words = _message.trimRight().split(RegExp(r'\s+'));
    final prefix = endsWithSpace
        ? _message
        : completesCurrentWord
        ? '${_message.trim()} '
        : _message.trim().isEmpty
        ? ''
        : words.length > 1
        ? '${words.sublist(0, words.length - 1).join(' ')} '
        : '';
    setState(() {
      _message = '$prefix${suggestion.toUpperCase()} ';
      _selectedSuggestion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > constraints.maxHeight;
                  return switch (widget.controlStyle) {
                    ControlStyle.edges => _edgesLayout(isWide),
                    ControlStyle.cross => _crossLayout(isWide),
                  };
                },
              ),
            ),
          ),
          if (kDebugMode) _debugGazeDot(),
        ],
      ),
    );
  }

  /// Ponto da previsão, no mesmo espaço [0,1] da calibração. Só em debug.
  Widget _debugGazeDot() {
    final p = _gaze?.point;
    if (p == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment(
            p.x.clamp(0.0, 1.0) * 2 - 1,
            p.y.clamp(0.0, 1.0) * 2 - 1,
          ),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.cyanAccent.withValues(alpha: 0.35),
              border: Border.all(color: Colors.cyanAccent, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  // --- Arranjo de bordas ---------------------------------------------------

  /// Setas emoldurando a tela; mensagem, câmera, teclado e confirmar no miolo.
  Widget _edgesLayout(bool isWide) {
    return EdgeControls(
      onCommand: _handleCommand,
      activeCommand: _tracker?.dwellCommand,
      // Confirmar fica dentro da moldura, longe das bordas: é o comando que
      // não pode ser disparado por engano.
      child: isWide ? _edgesCenterWide() : _edgesCenterTall(),
    );
  }

  /// Paisagem: o miolo é baixo, então confirmar vai para a lateral em vez de
  /// consumir mais uma faixa de altura que falta ao teclado.
  Widget _edgesCenterWide() {
    return Column(
      children: [
        _header(true),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _keyboard()),
              const SizedBox(width: 12),
              SizedBox(width: 140, child: _confirmButton()),
            ],
          ),
        ),
      ],
    );
  }

  /// Retrato: o miolo é estreito, então o teclado recebe proporção fixa para
  /// as teclas não virarem pílulas altas, e confirmar ocupa a faixa de baixo.
  Widget _edgesCenterTall() {
    return Column(
      children: [
        _header(false),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _keyboardAspectRatioTall,
              child: _keyboard(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 68, child: _confirmButton()),
      ],
    );
  }

  Widget _confirmButton() {
    return GazeButton(
      command: GazeCommand.select,
      iconSize: 28,
      style: GazeButtonStyle.primary,
      showLabel: true,
      onPressed: () => _handleCommand(GazeCommand.select),
    );
  }

  // --- Arranjo em cruz -----------------------------------------------------

  Widget _crossLayout(bool isWide) {
    return Column(
      children: [
        _header(isWide),
        const SizedBox(height: 12),
        Expanded(
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: DirectionPad(onCommand: _handleCommand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _keyboard()),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DirectionPad(onCommand: _handleCommand),
                    ),
                    const SizedBox(height: 12),
                    Expanded(flex: 2, child: _keyboard()),
                  ],
                ),
        ),
      ],
    );
  }

  // --- Partes comuns -------------------------------------------------------

  /// Cabeçalho: mensagem à esquerda e uma prévia compacta da câmera à direita.
  ///
  /// A câmera só precisa ser grande o suficiente para o usuário conferir o
  /// enquadramento do rosto — o espaço economizado vai para as setas.
  Widget _header(bool isWide) {
    return SizedBox(
      height: isWide ? 112 : 152,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MessageBar(
              text: _message,
              suggestions: _suggestions,
              selectedSuggestionIndex: _selectedSuggestion,
              onSuggestionTap: _acceptSuggestion,
            ),
          ),
          const SizedBox(width: 12),
          _gazeStatus(),
          const SizedBox(width: 12),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: CameraView(onControllerReady: _onCameraReady),
          ),
        ],
      ),
    );
  }

  /// Estado do rastreador: um toque calibra, e o ícone diz por que ele não está
  /// funcionando quando não está.
  Widget _gazeStatus() {
    final tracker = _tracker;
    final (IconData icon, String tip) = switch ((tracker, _gaze, _gazeError)) {
      (_, _, final String e) when e.isNotEmpty => (
        Icons.error_outline,
        'Falhou: \$e',
      ),
      (null, _, _) => (Icons.hourglass_empty, 'Carregando o rastreador...'),
      (_, final g?, _) when !g.faceFound => (
        Icons.face_retouching_off,
        'Rosto não encontrado',
      ),
      (_, final g?, _) when g.eyesFound == 0 => (
        Icons.visibility_off,
        'Pupilas não detectadas',
      ),
      (final t?, _, _) when t.map == null => (
        Icons.adjust,
        'Detectando · toque para calibrar',
      ),
      _ => (Icons.visibility, 'Rastreando · toque para recalibrar'),
    };
    return Tooltip(
      message: tip,
      child: IconButton.filledTonal(
        onPressed: tracker == null ? null : _calibrate,
        icon: Icon(icon),
      ),
    );
  }

  Widget _keyboard() {
    return OnScreenKeyboard(
      row: _selectedSuggestion == null ? _row : -1,
      column: _column,
      onKeyTap: _pressKey,
    );
  }
}
