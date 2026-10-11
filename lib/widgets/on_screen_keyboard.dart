import 'package:flutter/material.dart';

import '../models/keyboard_layout.dart';

/// Teclado na tela com uma tecla destacada por vez.
///
/// O destaque ([row]/[column]) é o que as setas movem. Tocar direto numa tecla
/// também funciona — útil para testar sem o eye tracking.
class OnScreenKeyboard extends StatelessWidget {
  const OnScreenKeyboard({
    super.key,
    required this.row,
    required this.column,
    required this.onKeyTap,
    this.speakEnabled = false,
    this.speakLabel = 'FALAR',
  });

  final int row;
  final int column;
  final bool speakEnabled;
  final String speakLabel;

  /// Recebe a posição da tecla tocada.
  final void Function(int row, int column) onKeyTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var r = 0; r < kKeyboardRows.length; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < kKeyboardRows[r].length; c++)
                  Expanded(
                    flex: kKeyboardRows[r][c].flex,
                    child: _Key(
                      keyDef: kKeyboardRows[r][c],
                      selected: r == row && c == column,
                      enabled:
                          kKeyboardRows[r][c].action != KeyAction.speak ||
                          speakEnabled,
                      label: kKeyboardRows[r][c].action == KeyAction.speak
                          ? speakLabel
                          : kKeyboardRows[r][c].label,
                      onTap: () => onKeyTap(r, c),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.keyDef,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final KeyDef keyDef;
  final bool selected;
  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background = selected
        ? scheme.primary
        : keyDef.isCharacter
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerHighest;
    final foreground = enabled
        ? selected
              ? scheme.onPrimary
              : scheme.onSurface
        : selected
        ? scheme.onPrimary.withValues(alpha: 0.5)
        : scheme.onSurface.withValues(alpha: 0.38);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: selected
                ? BorderSide(color: scheme.onPrimaryContainer, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
