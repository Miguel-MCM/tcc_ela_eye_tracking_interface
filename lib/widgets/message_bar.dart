import 'package:flutter/material.dart';

/// Faixa superior com o texto que está sendo composto.
class MessageBar extends StatelessWidget {
  const MessageBar({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEmpty = text.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        isEmpty ? 'Sua mensagem aparece aqui' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
          fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}
