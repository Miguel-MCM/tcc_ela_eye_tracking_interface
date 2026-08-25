import 'package:flutter/material.dart';

import '../models/gaze_command.dart';
import 'gaze_button.dart';

/// Setas de navegação em cruz, com o botão de confirmação no centro.
///
/// Arranjo compacto: ocupa uma área contígua da tela e mantém as quatro setas
/// equidistantes do centro. Comparar com [EdgeControls], que espalha as setas
/// pelas bordas.
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
        // A cruz é quadrada para as setas ficarem equidistantes do centro.
        final side = constraints.biggest.shortestSide;
        final cell = side / 3;

        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Column(
              children: [
                _row([null, GazeCommand.up, null], cell),
                _row(
                  [GazeCommand.left, GazeCommand.select, GazeCommand.right],
                  cell,
                ),
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
                  : Padding(
                      padding: const EdgeInsets.all(3),
                      child: GazeButton(
                        command: command,
                        iconSize: cell * 0.55,
                        active: command == activeCommand,
                        style: command == GazeCommand.select
                            ? GazeButtonStyle.primary
                            : GazeButtonStyle.neutral,
                        borderRadius:
                            command == GazeCommand.select ? cell : 10,
                        onPressed: () => onCommand(command),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
