import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';
import 'typing_event.dart';
import 'typing_metrics.dart';

/// Registra a digitação de uma sessão e grava um JSON com o log bruto e as
/// métricas calculadas ([TypingMetrics]).
///
/// No Android o arquivo fica em
/// `/sdcard/Android/data/<pacote>/files/typing_metrics/`, acessível com
/// `adb pull` sem root.
class TypingMetricsRecorder {
  TypingMetricsRecorder({
    DateTime Function()? clock,
    Future<Directory> Function()? directory,
  }) : _clock = clock ?? DateTime.now,
       _directory = directory ?? _defaultDirectory {
    startedAt = _clock();
  }

  static const schemaVersion = 1;

  final DateTime Function() _clock;
  final Future<Directory> Function() _directory;
  late final DateTime startedAt;
  final _events = <TypingEvent>[];
  TypingEvent? _lastSuggestions;
  Future<File?> _lastSave = Future.value();

  List<TypingEvent> get events => List.unmodifiable(_events);

  TypingMetrics get metrics => TypingMetrics.fromEvents(_events);

  Duration get _now => _clock().difference(startedAt);

  void recordCommand(GazeCommand command, InputSource source) {
    _events.add(TypingEvent.command(_now, command, source));
  }

  /// Registra [key] acionada em ([row], [column]); [text] é a mensagem depois.
  void recordKey(KeyDef key, int row, int column, String text) {
    _events.add(
      TypingEvent.key(
        _now,
        action: key.action,
        label: key.label,
        row: row,
        column: column,
        text: text,
      ),
    );
  }

  /// Registra as sugestões exibidas para [text], só quando elas mudam.
  void recordSuggestions(String text, List<String> suggestions) {
    final last = _lastSuggestions;
    if (last != null &&
        last.text == text &&
        listEquals(last.suggestions, suggestions)) {
      return;
    }
    final event = TypingEvent.suggestions(
      _now,
      text: text,
      suggestions: List.unmodifiable(suggestions),
    );
    _events.add(event);
    _lastSuggestions = event;
  }

  void recordAcceptance(String suggestion, int rank, String text) {
    _events.add(
      TypingEvent.acceptance(
        _now,
        suggestion: suggestion,
        rank: rank,
        text: text,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'startedAt': startedAt.toIso8601String(),
    'savedAt': _clock().toIso8601String(),
    ...metrics.toJson(),
    'events': [for (final event in _events) event.toJson()],
  };

  /// Grava a sessão inteira, sobrescrevendo o arquivo dela. Retorna null se
  /// não conseguir gravar, para nunca interromper a comunicação do usuário.
  Future<File?> save() {
    final write = _lastSave.then((_) => _write());
    _lastSave = write;
    return write;
  }

  Future<File?> _write() async {
    try {
      final directory = await _directory();
      await directory.create(recursive: true);
      final file = File('${directory.path}/session_${_fileStamp()}.json');
      final json = const JsonEncoder.withIndent('  ').convert(toJson());
      return await file.writeAsString(json, flush: true);
    } catch (error, stackTrace) {
      debugPrint('[metrics] falha ao gravar a sessão: $error\n$stackTrace');
      return null;
    }
  }

  /// Data e hora do início sem ":" para o nome do arquivo valer em qualquer
  /// sistema para onde ele for copiado.
  String _fileStamp() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = startedAt;
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static Future<Directory> _defaultDirectory() async {
    final external = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : null;
    final base = external ?? await getApplicationDocumentsDirectory();
    return Directory('${base.path}/typing_metrics');
  }
}
