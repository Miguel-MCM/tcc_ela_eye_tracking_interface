import 'package:flutter/material.dart';

import '../models/gaze_command.dart';

/// Setas de navegação em cruz, com o botão de confirmação no centro.
///
/// É o ponto de entrada manual dos comandos; o eye tracking vai alimentar o
/// mesmo [onCommand]. [activeCommand] permite destacar a direção que o olhar
/// está apontando no momento.
class DirectionPad extends StatelessWidget {
  const DirectionPad({
    super.key,
    required this.onCommand,
    this.activeCommand,
  });

  final ValueChanged<GazeCommand> onCommand;
  final GazeCommand? activeCommand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final cell = side / 3;

        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Column(
              children: [
                _row([null, GazeCommand.up, null], cell),
                _row([GazeCommand.left, GazeCommand.select, GazeCommand.right], cell),
                _row([null, GazeCommand.down, null], cell),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(List<GazeCommand?> commands, double cell) {
    return SizedBox(
      height: cell,
      child: Row(
        children: [
          for (final command in commands)
            SizedBox(
              width: cell,
              height: cell,
              child: command == null
                  ? const SizedBox.shrink()
                  : _PadButton(
                      command: command,
                      active: command == activeCommand,
                      onPressed: () => onCommand(command),
                    ),
            ),
        ],
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.command,
    required this.active,
    required this.onPressed,
  });

  final GazeCommand command;
  final bool active;
  final VoidCallback onPressed;

  static const _icons = {
    GazeCommand.up: Icons.keyboard_arrow_up,
    GazeCommand.down: Icons.keyboard_arrow_down,
    GazeCommand.left: Icons.keyboard_arrow_left,
    GazeCommand.right: Icons.keyboard_arrow_right,
    GazeCommand.select: Icons.check,
  };

  static const _labels = {
    GazeCommand.up: 'Cima',
    GazeCommand.down: 'Baixo',
    GazeCommand.left: 'Esquerda',
    GazeCommand.right: 'Direita',
    GazeCommand.select: 'Confirmar',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelect = command == GazeCommand.select;

    final background = active
        ? scheme.primary
        : isSelect
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = active
        ? scheme.onPrimary
        : isSelect
            ? scheme.onSecondaryContainer
            : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Semantics(
        button: true,
        label: _labels[command],
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isSelect ? 999 : 10),
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isSelect ? 999 : 10),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(_icons[command], color: foreground, size: 34),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
