import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';

/// De onde veio um comando: do rastreador ocular ou de um toque na tela.
///
/// Os toques servem para testar sem a câmera; separá-los permite descartar
/// essas interações na análise.
enum InputSource { gaze, touch }

enum TypingEventType { command, key, suggestions, acceptance }

/// Um evento bruto da digitação, com o instante relativo ao início da sessão.
///
/// Os eventos são a fonte da verdade: as métricas são sempre recalculadas a
/// partir deles, então mudar uma definição não exige repetir os testes.
class TypingEvent {
  const TypingEvent._(
    this.type,
    this.time, {
    this.command,
    this.source,
    this.action,
    this.label,
    this.row,
    this.column,
    this.text,
    this.suggestions,
    this.suggestion,
    this.rank,
  });

  /// Um comando de navegação ou seleção, seja do olhar ou de um toque.
  const TypingEvent.command(
    Duration time,
    GazeCommand command,
    InputSource source,
  ) : this._(TypingEventType.command, time, command: command, source: source);

  /// Uma tecla acionada; [text] é a mensagem depois dela.
  const TypingEvent.key(
    Duration time, {
    required KeyAction action,
    required String label,
    required int row,
    required int column,
    required String text,
  }) : this._(
         TypingEventType.key,
         time,
         action: action,
         label: label,
         row: row,
         column: column,
         text: text,
       );

  /// As sugestões que passaram a ser exibidas para a mensagem [text].
  const TypingEvent.suggestions(
    Duration time, {
    required String text,
    required List<String> suggestions,
  }) : this._(
         TypingEventType.suggestions,
         time,
         text: text,
         suggestions: suggestions,
       );

  /// Uma sugestão aceita na posição [rank] (0 é a primeira); [text] é a
  /// mensagem depois dela.
  const TypingEvent.acceptance(
    Duration time, {
    required String suggestion,
    required int rank,
    required String text,
  }) : this._(
         TypingEventType.acceptance,
         time,
         suggestion: suggestion,
         rank: rank,
         text: text,
       );

  factory TypingEvent.fromJson(Map<String, Object?> json) => TypingEvent._(
    TypingEventType.values.byName(json['type']! as String),
    Duration(milliseconds: json['t']! as int),
    command: switch (json['command']) {
      final String name => GazeCommand.values.byName(name),
      _ => null,
    },
    source: switch (json['source']) {
      final String name => InputSource.values.byName(name),
      _ => null,
    },
    action: switch (json['action']) {
      final String name => KeyAction.values.byName(name),
      _ => null,
    },
    label: json['label'] as String?,
    row: json['row'] as int?,
    column: json['column'] as int?,
    text: json['text'] as String?,
    suggestions: (json['suggestions'] as List<Object?>?)?.cast<String>(),
    suggestion: json['suggestion'] as String?,
    rank: json['rank'] as int?,
  );

  final TypingEventType type;
  final Duration time;
  final GazeCommand? command;
  final InputSource? source;
  final KeyAction? action;
  final String? label;
  final int? row;
  final int? column;
  final String? text;
  final List<String>? suggestions;
  final String? suggestion;
  final int? rank;

  Map<String, Object?> toJson() => {
    't': time.inMilliseconds,
    'type': type.name,
    if (command != null) 'command': command!.name,
    if (source != null) 'source': source!.name,
    if (action != null) 'action': action!.name,
    if (label != null) 'label': label,
    if (row != null) 'row': row,
    if (column != null) 'column': column,
    if (text != null) 'text': text,
    if (suggestions != null) 'suggestions': suggestions,
    if (suggestion != null) 'suggestion': suggestion,
    if (rank != null) 'rank': rank,
  };
}
