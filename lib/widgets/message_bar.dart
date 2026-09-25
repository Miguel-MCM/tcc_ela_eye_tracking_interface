import 'package:flutter/material.dart';

/// Faixa superior com o texto que está sendo composto.
class MessageBar extends StatelessWidget {
  const MessageBar({
    super.key,
    required this.text,
    this.suggestions = const [],
    this.selectedSuggestionIndex,
    this.onSuggestionTap,
  });

  final String text;
  final List<String> suggestions;
  final int? selectedSuggestionIndex;
  final ValueChanged<String>? onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEmpty = text.isEmpty;
    final visibleSuggestions = isEmpty ? const <String>[] : suggestions;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // Alinhado à esquerda e centrado na vertical: a faixa agora divide a
      // altura do cabeçalho com a prévia da câmera.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isEmpty ? 'Sua mensagem aparece aqui' : text,
            maxLines: visibleSuggestions.isEmpty ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          if (visibleSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visibleSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final suggestion = visibleSuggestions[index];
                  final selected = index == selectedSuggestionIndex;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'Usar sugestão $suggestion',
                    child: ActionChip(
                      label: Text(suggestion.toUpperCase()),
                      backgroundColor: selected ? scheme.primary : null,
                      labelStyle: selected
                          ? TextStyle(color: scheme.onPrimary)
                          : null,
                      side: selected
                          ? BorderSide(
                              color: scheme.onPrimaryContainer,
                              width: 2,
                            )
                          : null,
                      onPressed: onSuggestionTap == null
                          ? null
                          : () => onSuggestionTap!(suggestion),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
