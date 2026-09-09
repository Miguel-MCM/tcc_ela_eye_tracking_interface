import 'package:flutter/material.dart';

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

  List<String> get _suggestions => _wordPredictor.suggest(_message);

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
        _pressKey(_row, _column);
    }
  }

  void _moveRow(int delta) {
    final row = (_row + delta).clamp(0, kKeyboardRows.length - 1);
    setState(() {
      _row = row;
      // As linhas têm tamanhos diferentes: ao mudar de linha a coluna pode
      // ficar fora do intervalo.
      _column = _column.clamp(0, kKeyboardRows[row].length - 1);
    });
  }

  void _moveColumn(int delta) {
    setState(() {
      _column = (_column + delta).clamp(0, kKeyboardRows[_row].length - 1);
    });
  }

  void _pressKey(int row, int column) {
    final keyDef = kKeyboardRows[row][column];
    setState(() {
      _row = row;
      _column = column;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
    );
  }

  // --- Arranjo de bordas ---------------------------------------------------

  /// Setas emoldurando a tela; mensagem, câmera, teclado e confirmar no miolo.
  Widget _edgesLayout(bool isWide) {
    return EdgeControls(
      onCommand: _handleCommand,
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
              onSuggestionTap: _acceptSuggestion,
            ),
          ),
          const SizedBox(width: 12),
          const AspectRatio(aspectRatio: 3 / 4, child: CameraView()),
        ],
      ),
    );
  }

  Widget _keyboard() {
    return OnScreenKeyboard(row: _row, column: _column, onKeyTap: _pressKey);
  }
}
