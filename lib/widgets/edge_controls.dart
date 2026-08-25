import 'package:flutter/material.dart';

import '../models/gaze_command.dart';
import 'gaze_button.dart';

/// Setas ancoradas nas quatro bordas da tela, emoldurando [child].
///
/// A separação angular entre os alvos é o que determina o erro de
/// classificação da direção do olhar: quanto mais longe uma seta está da
/// outra, menor a chance de o rastreador confundir "cima" com "direita". Por
/// isso as setas vão para os extremos, e não para uma cruz compacta no meio.
///
/// O comando [GazeCommand.select] não aparece aqui — quem monta [child] decide
/// onde colocá-lo.
class EdgeControls extends StatelessWidget {
  const EdgeControls({
    super.key,
    required this.onCommand,
    required this.child,
    this.activeCommand,
  });

  final ValueChanged<GazeCommand> onCommand;
  final Widget child;
  final GazeCommand? activeCommand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cada par de barras é dimensionado pelo eixo em que ele se move: as
        // horizontais pela altura, as verticais pela largura. Um fator único
        // deixaria as barras finas demais em paisagem.
        //
        // As barras são finas no eixo que interessa e longas no outro: o que
        // distingue "esquerda" de "direita" é o erro horizontal do olhar, e
        // uma barra alta e estreita na borda cobre bem essa discriminação sem
        // roubar largura do teclado.
        final horizontalBar = (constraints.maxHeight * 0.16).clamp(56.0, 150.0);
        final verticalBar = (constraints.maxWidth * 0.14).clamp(52.0, 160.0);

        return Column(
          children: [
            SizedBox(
              height: horizontalBar,
              child: _bar(GazeCommand.up, horizontalBar),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: verticalBar,
                    child: _bar(GazeCommand.left, verticalBar),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: child),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: verticalBar,
                    child: _bar(GazeCommand.right, verticalBar),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: horizontalBar,
              child: _bar(GazeCommand.down, horizontalBar),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(GazeCommand command, double thickness) {
    return GazeButton(
      command: command,
      iconSize: thickness * 0.7,
      active: command == activeCommand,
      onPressed: () => onCommand(command),
    );
  }
}
