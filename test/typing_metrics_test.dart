import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/metrics/typing_event.dart';
import 'package:tcc_ela_eye_tracking_interface/metrics/typing_metrics.dart';
import 'package:tcc_ela_eye_tracking_interface/metrics/typing_metrics_recorder.dart';
import 'package:tcc_ela_eye_tracking_interface/models/gaze_command.dart';
import 'package:tcc_ela_eye_tracking_interface/models/keyboard_layout.dart';

/// Simula a tela: cada comando leva um segundo e as teclas alteram a mensagem
/// como em CommunicatorScreen.
class _Session {
  var now = DateTime(2026, 10, 21, 9);
  var text = '';
  late final recorder = TypingMetricsRecorder(clock: () => now);

  TypingMetrics get metrics => recorder.metrics;

  void move(int count) {
    for (var i = 0; i < count; i++) {
      _command(GazeCommand.right);
    }
  }

  void press(String label, {int moves = 0}) {
    move(moves);
    _command(GazeCommand.select);
    final (row, column) = _find(label);
    final key = kKeyboardRows[row][column];
    text = switch (key.action) {
      KeyAction.character => text + key.label,
      KeyAction.space => text.endsWith(' ') ? text : '$text ',
      KeyAction.backspace =>
        text.isEmpty ? text : text.substring(0, text.length - 1),
      KeyAction.clear => '',
      KeyAction.speak => text,
    };
    recorder.recordKey(key, row, column, text);
  }

  void type(String letters) {
    for (final letter in letters.split('')) {
      press(letter);
    }
  }

  void show(List<String> suggestions) =>
      recorder.recordSuggestions(text, suggestions);

  void accept(String suggestion, int rank, String result) {
    _command(GazeCommand.select);
    text = result;
    recorder.recordAcceptance(suggestion, rank, text);
  }

  void _command(GazeCommand command) {
    now = now.add(const Duration(seconds: 1));
    recorder.recordCommand(command, InputSource.gaze);
  }

  static (int, int) _find(String label) {
    for (var r = 0; r < kKeyboardRows.length; r++) {
      for (var c = 0; c < kKeyboardRows[r].length; c++) {
        if (kKeyboardRows[r][c].label == label) return (r, c);
      }
    }
    throw ArgumentError(label);
  }
}

void main() {
  group('KSPC, economia e WPM', () {
    test('digitar pelo caminho mínimo não economiza nada', () {
      // O em (0, 8), I em (0, 7) e FALAR em (3, 0), partindo de (0, 0).
      final session = _Session()
        ..press('O', moves: 8)
        ..press('I', moves: 1)
        ..press('FALAR', moves: 6);

      final phrase = session.metrics.phrases.single;
      final counts = phrase.counts;
      expect(phrase.text, 'OI');
      expect(counts.characters, 2);
      expect(counts.interactions, 18);
      expect(counts.baselineInteractions, 18);
      expect(counts.keystrokeSavings, 0);
      expect(counts.kspc, 9);
      expect(counts.kspcSelections, 1.5);
      // Do primeiro comando (1 s) ao FALAR (18 s).
      expect(counts.duration, const Duration(seconds: 17));
      expect(counts.wordsPerMinute, closeTo(2 / 5 / (17 / 60), 1e-9));
      expect(counts.gazeInteractions, 18);
      expect(counts.touchInteractions, 0);
    });

    test('aceitar uma sugestão economiza seleções', () {
      final session = _Session()..press('A');
      session
        ..show(['abrir', 'água'])
        ..press('G')
        ..show(['água'])
        ..accept('água', 0, 'ÁGUA ')
        ..press('FALAR');

      final counts = session.metrics.phrases.single.counts;
      // A, G, sugestão e FALAR contra A, G, U, A e FALAR.
      expect(counts.selections, 4);
      expect(counts.baselineSelections, 5);
      expect(counts.keystrokeSavingsSelections, closeTo(0.2, 1e-9));
    });
  });

  group('predição', () {
    test('registra quando a palavra apareceu e em que posição', () {
      final session = _Session()..press('A');
      session
        ..show(['abrir', 'água'])
        ..press('G')
        ..show(['água'])
        ..accept('água', 0, 'ÁGUA ')
        ..press('FALAR');

      final phrase = session.metrics.phrases.single;
      final word = phrase.words.single;
      expect(word.word, 'ÁGUA');
      expect(word.predictedAfter, 1);
      expect(word.top1After, 2);
      expect(word.acceptedRank, 0);
      expect(phrase.counts.predictionAccuracy, 1);
      expect(phrase.counts.completionRate, 1);
      expect(phrase.counts.acceptedRanks, {0: 1});
    });

    test('próxima palavra sugerida sem espaço conta como prevista com 0 '
        'letras', () {
      final session = _Session()..type('EU');
      session
        ..show(['quero'])
        ..accept('quero', 0, 'EU QUERO ')
        ..press('FALAR');

      final counts = session.metrics.phrases.single.counts;
      final words = session.metrics.phrases.single.words;
      expect(words.map((w) => w.predictedAfter), [null, 0]);
      expect(counts.predictionAccuracy, 0.5);
      expect(counts.completionRate, 0.5);
      expect(counts.suggestionUtilization, 1);
    });

    test('palavra prevista mas digitada reduz a utilização', () {
      final session = _Session()..press('C');
      session
        ..show(['casa'])
        ..type('ASA')
        ..press('FALAR');

      final counts = session.metrics.phrases.single.counts;
      expect(counts.predictionAccuracy, 1);
      expect(counts.completionRate, 0);
      expect(counts.suggestionUtilization, 0);
    });
  });

  group('erros', () {
    test('caracteres apagados contam como erros corrigidos', () {
      final session = _Session()
        ..type('AX')
        ..press('APAGAR')
        ..press('B')
        ..press('FALAR');

      final counts = session.metrics.phrases.single.counts;
      expect(session.metrics.phrases.single.text, 'AB');
      expect(counts.backspaces, 1);
      expect(counts.erasedCharacters, 1);
      expect(counts.correctedErrorRate, closeTo(1 / 3, 1e-9));
    });

    test('sugestão aceita e apagada é rejeitada', () {
      final session = _Session()..press('C');
      session
        ..show(['casa'])
        ..accept('casa', 0, 'CASA ');
      for (var i = 0; i < 5; i++) {
        session.press('APAGAR');
      }
      session
        ..type('OI')
        ..press('FALAR');

      final counts = session.metrics.phrases.single.counts;
      expect(counts.acceptances, 1);
      expect(counts.rejectedAcceptances, 1);
      expect(counts.rejectedAcceptanceRate, 1);
      expect(counts.completionRate, 0);
      expect(counts.erasedCharacters, 5);
    });

    test('limpar a frase anterior não é erro', () {
      final session = _Session()
        ..press('A')
        ..press('FALAR')
        // FALAR (3, 0) → LIMPAR (3, 3) → B (2, 4) → FALAR, pelo caminho mínimo.
        ..press('LIMPAR', moves: 3)
        ..press('B', moves: 2)
        ..press('FALAR', moves: 4);

      final metrics = session.metrics;
      expect(metrics.phrases, hasLength(2));
      final second = metrics.phrases.last.counts;
      expect(metrics.phrases.last.text, 'B');
      expect(second.clears, 1);
      expect(second.erasedCharacters, 0);
      expect(second.baselineInteractions, 12);
      expect(second.keystrokeSavings, 0);
      expect(metrics.summary.characters, 2);
    });

    test('falar de novo a mesma mensagem não cria frase', () {
      final session = _Session()
        ..press('A')
        ..press('FALAR')
        ..press('FALAR');

      expect(session.metrics.phrases, hasLength(1));
    });

    test('continuar a mensagem falada conta só o trecho novo', () {
      final session = _Session()
        ..type('OI')
        ..press('FALAR')
        ..press('ESPAÇO')
        ..type('TCHAU')
        ..press('FALAR');

      expect(session.metrics.phrases.last.text, 'TCHAU');
      expect(session.metrics.phrases.last.words.single.word, 'TCHAU');
    });
  });

  group('gravação', () {
    test('não repete sugestões iguais', () {
      final session = _Session()
        ..show(['a'])
        ..show(['a'])
        ..show(['b']);

      expect(session.recorder.events, hasLength(2));
    });

    test('eventos sobrevivem à ida e volta pelo JSON', () {
      final session = _Session()..press('C');
      session
        ..show(['casa'])
        ..accept('casa', 0, 'CASA ')
        ..press('FALAR');

      final events = session.recorder.events;
      final decoded = [
        for (final event in jsonDecode(jsonEncode(events)) as List<Object?>)
          TypingEvent.fromJson(event! as Map<String, Object?>),
      ];
      expect(
        jsonEncode(TypingMetrics.fromEvents(decoded)),
        jsonEncode(TypingMetrics.fromEvents(events)),
      );
    });

    test('grava um JSON com resumo, frases e eventos', () async {
      final directory = await Directory.systemTemp.createTemp('metrics');
      addTearDown(() => directory.delete(recursive: true));
      var now = DateTime(2026, 10, 21, 9, 5, 7);
      final recorder = TypingMetricsRecorder(
        clock: () => now,
        directory: () async => directory,
      );
      final key = kKeyboardRows[0][0];
      recorder
        ..recordCommand(GazeCommand.select, InputSource.gaze)
        ..recordKey(key, 0, 0, 'Q');
      now = now.add(const Duration(seconds: 2));
      recorder
        ..recordCommand(GazeCommand.select, InputSource.gaze)
        ..recordKey(kKeyboardRows[3][0], 3, 0, 'Q');

      final file = await recorder.save();

      expect(file!.path, endsWith('session_20261021_090507.json'));
      final json = jsonDecode(await file.readAsString()) as Map;
      expect(json['schemaVersion'], 1);
      expect(json['summary']['phrases'], 1);
      expect(json['summary']['characters'], 1);
      expect(json['phrases'], hasLength(1));
      expect(json['events'], hasLength(4));
    });
  });
}
