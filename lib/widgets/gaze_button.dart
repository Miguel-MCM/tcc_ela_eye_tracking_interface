import 'package:flutter/material.dart';

import '../models/gaze_command.dart';

/// Ênfase visual do botão.
enum GazeButtonStyle {
  /// Setas de navegação.
  neutral,

  /// Ação de confirmar — precisa se distinguir das setas à primeira vista.
  primary,
}

/// Botão que emite um [GazeCommand].
///
/// Compartilhado pelos dois arranjos de controle ([DirectionPad] e
/// [EdgeControls]) para que a aparência e a área de toque sejam idênticas nos
/// dois — a comparação entre eles precisa medir só a geometria.
class GazeButton extends StatelessWidget {
  const GazeButton({
    super.key,
    required this.command,
    required this.iconSize,
    required this.onPressed,
    this.active = false,
    this.style = GazeButtonStyle.neutral,
    this.borderRadius = 16,
    this.showLabel = false,
  });

  final GazeCommand command;

  /// Acompanha o tamanho do botão: alvo grande com ícone pequeno é difícil de
  /// mirar com o olhar.
  final double iconSize;

  final VoidCallback onPressed;

  /// Destaca a direção que o olhar está apontando no momento.
  final bool active;

  final GazeButtonStyle style;
  final double borderRadius;
  final bool showLabel;

  static const icons = {
    GazeCommand.up: Icons.keyboard_arrow_up,
    GazeCommand.down: Icons.keyboard_arrow_down,
    GazeCommand.left: Icons.keyboard_arrow_left,
    GazeCommand.right: Icons.keyboard_arrow_right,
    GazeCommand.select: Icons.check,
  };

  static const labels = {
    GazeCommand.up: 'Cima',
    GazeCommand.down: 'Baixo',
    GazeCommand.left: 'Esquerda',
    GazeCommand.right: 'Direita',
    GazeCommand.select: 'Confirmar',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPrimary = style == GazeButtonStyle.primary;

    final background = active
        ? scheme.primary
        : isPrimary
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = active
        ? scheme.onPrimary
        : isPrimary
            ? scheme.onSecondaryContainer
            : scheme.onSurface;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );

    return Semantics(
      button: true,
      label: labels[command],
      child: Material(
        color: background,
        shape: shape,
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: Center(
            child: showLabel
                // Encolhe em vez de estourar quando o botão é estreito.
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[command],
                            color: foreground,
                            size: iconSize,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            labels[command]!.toUpperCase(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Icon(icons[command], color: foreground, size: iconSize),
          ),
        ),
      ),
    );
  }
}
