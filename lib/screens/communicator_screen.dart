import 'package:flutter/material.dart';

import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';
import '../widgets/camera_view.dart';
import '../widgets/direction_pad.dart';
import '../widgets/message_bar.dart';
import '../widgets/on_screen_keyboard.dart';

/// Tela principal: prévia da câmera, setas de navegação e teclado.
///
/// Toda a interação passa por [_handleCommand]. Quando o eye tracking entrar,
/// basta ele chamar esse mesmo método — nada aqui precisa mudar.
class CommunicatorScreen extends StatefulWidget {
  const CommunicatorScreen({super.key});

  @override
  State<CommunicatorScreen> createState() => _CommunicatorScreenState();
}

class _CommunicatorScreenState extends State<CommunicatorScreen> {
  String _message = '';
  int _row = 0;
  int _column = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > constraints.maxHeight;
              return Column(
                children: [
                  MessageBar(text: _message),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isWide ? _wideLayout() : _tallLayout(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Paisagem: câmera e setas numa coluna à esquerda, teclado ocupando o resto.
  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              const Expanded(child: CameraView()),
              const SizedBox(height: 12),
              Expanded(child: DirectionPad(onCommand: _handleCommand)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 5, child: _keyboard()),
      ],
    );
  }

  /// Retrato: câmera e setas lado a lado em cima, teclado embaixo.
  Widget _tallLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Row(
            children: [
              const Expanded(child: CameraView()),
              const SizedBox(width: 12),
              Expanded(child: DirectionPad(onCommand: _handleCommand)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(flex: 5, child: _keyboard()),
      ],
    );
  }

  Widget _keyboard() {
    return OnScreenKeyboard(
      row: _row,
      column: _column,
      onKeyTap: _pressKey,
    );
  }
}
