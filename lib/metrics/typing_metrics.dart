import 'dart:math';

import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';
import '../models/word_predictor.dart';
import 'typing_event.dart';

/// Métricas de digitação calculadas a partir do log de eventos.
///
/// No uso livre não há frase-alvo, então a unidade de análise é a frase
/// falada: tudo o que acontece entre um FALAR e o seguinte. O texto produzido
/// é o que foi falado, excluindo o que já estava na mensagem antes.
///
/// Referências: KSPC e erros corrigidos seguem Soukoreff & MacKenzie (2003);
/// WPM usa a convenção de 5 caracteres por palavra.
class TypingMetrics {
  TypingMetrics._(this.phrases, this.summary);

  factory TypingMetrics.fromEvents(
    Iterable<TypingEvent> events, {
    List<List<KeyDef>> layout = kKeyboardRows,
  }) {
    final keyboard = _Keyboard(layout);
    final phrases = <PhraseMetrics>[];
    var text = '';
    var position = (0, 0);
    TypingEvent? lastShown;
    var segment = _Segment(startText: '', position: position, shown: []);

    for (final event in events) {
      switch (event.type) {
        case TypingEventType.command:
          segment.start ??= event.time;
          segment.counts.interactions++;
          if (event.command == GazeCommand.select) {
            segment.counts.selections++;
          }
          if (event.source == InputSource.gaze) {
            segment.counts.gazeInteractions++;
          } else {
            segment.counts.touchInteractions++;
          }
        case TypingEventType.suggestions:
          segment.shown.add(event);
          lastShown = event;
        case TypingEventType.acceptance:
          segment.start ??= event.time;
          segment.counts.acceptances++;
          segment.acceptances.add(event);
          // A sugestão reescreve a palavra parcial (com acentos, inclusive),
          // o que não é um erro corrigido.
          segment.protectedLength = min(
            segment.protectedLength,
            _commonPrefixLength(text, event.text!),
          );
          text = event.text!;
        case TypingEventType.key:
          segment.start ??= event.time;
          final after = event.text!;
          switch (event.action!) {
            case KeyAction.backspace:
              segment.counts.backspaces++;
              segment.erase(text.length, after.length);
            case KeyAction.clear:
              segment.counts.clears++;
              segment.erase(text.length, after.length);
            case KeyAction.character || KeyAction.space || KeyAction.speak:
              break;
          }
          text = after;
          position = (event.row!, event.column!);

          if (event.action == KeyAction.speak) {
            final phrase = segment.finish(after, event.time, keyboard);
            if (phrase != null) phrases.add(phrase);
            // A mensagem continua na tela depois de falada; as sugestões que
            // ela mostrava ainda valem para a próxima palavra.
            segment = _Segment(
              startText: after,
              position: position,
              shown: [?lastShown],
            );
          }
      }
    }

    final summary = TypingCounts();
    for (final phrase in phrases) {
      summary.add(phrase.counts);
    }
    return TypingMetrics._(phrases, summary);
  }

  final List<PhraseMetrics> phrases;

  /// Soma de todas as frases; as razões são recalculadas sobre os totais.
  final TypingCounts summary;

  Map<String, Object?> toJson() => {
    'summary': {'phrases': phrases.length, ...summary.toJson()},
    'phrases': [for (final phrase in phrases) phrase.toJson()],
  };
}

/// Uma frase falada e as métricas dela.
class PhraseMetrics {
  PhraseMetrics({
    required this.text,
    required this.start,
    required this.counts,
    required this.words,
  });

  /// Texto produzido nesta frase, sem o que já estava na mensagem.
  final String text;
  final Duration start;
  final TypingCounts counts;
  final List<WordEntry> words;

  Map<String, Object?> toJson() => {
    'text': text,
    'startSeconds': start.inMilliseconds / 1000,
    ...counts.toJson(),
    'words': [for (final word in words) word.toJson()],
  };
}

/// Como uma palavra da frase final foi prevista e inserida.
class WordEntry {
  WordEntry(this.word);

  final String word;

  /// Menor número de letras digitadas com a palavra entre as sugestões.
  int? predictedAfter;

  /// Menor número de letras digitadas com a palavra como primeira sugestão.
  int? top1After;

  /// Posição da sugestão aceita (0 é a primeira), ou null se foi digitada.
  int? acceptedRank;

  /// A palavra foi digitada por inteiro e só depois aceita como sugestão,
  /// como atalho para o espaço ou para o acento ("AGUA" → "ÁGUA ").
  bool shortcut = false;

  bool get predicted => predictedAfter != null;
  bool get accepted => acceptedRank != null;

  Map<String, Object?> toJson() => {
    'word': word,
    'entry': accepted
        ? 'suggestion'
        : shortcut
        ? 'shortcut'
        : 'typed',
    'predictedAfterCharacters': predictedAfter,
    'top1AfterCharacters': top1After,
    'acceptedRank': acceptedRank == null ? null : acceptedRank! + 1,
  };
}

/// Contagens de uma frase ou da sessão e as métricas derivadas delas.
///
/// Guardar contagens em vez de médias permite somar frases sem distorcer as
/// razões (micro-média).
class TypingCounts {
  Duration duration = Duration.zero;

  /// Caracteres produzidos, incluindo os espaços entre palavras.
  int characters = 0;
  int words = 0;

  /// Todos os comandos: movimentos e seleções.
  int interactions = 0;
  int selections = 0;
  int gazeInteractions = 0;
  int touchInteractions = 0;

  /// Comandos mínimos para produzir o mesmo texto sem autocomplete.
  int baselineInteractions = 0;
  int baselineSelections = 0;

  int backspaces = 0;
  int clears = 0;

  /// Caracteres desta frase que foram digitados e depois apagados.
  int erasedCharacters = 0;

  int acceptances = 0;

  /// Sugestões aceitas cuja palavra não ficou na frase falada.
  int rejectedAcceptances = 0;

  /// Sugestões aceitas com a palavra já digitada por inteiro. Não contam em
  /// [wordsAccepted], que assim nunca passa de [wordsPredicted].
  int shortcutAcceptances = 0;

  int wordsAccepted = 0;
  int wordsPredicted = 0;
  int wordsPredictedTop1 = 0;

  /// Soma de [WordEntry.predictedAfter] das palavras previstas.
  int charactersBeforePrediction = 0;

  /// Quantas sugestões foram aceitas em cada posição (0 é a primeira).
  final Map<int, int> acceptedRanks = {};

  /// Comandos por caractere produzido: o custo real para o usuário.
  double? get kspc => _ratio(interactions, characters);

  /// Seleções por caractere, comparável à literatura de teclados físicos.
  double? get kspcSelections => _ratio(selections, characters);

  /// Fração de comandos economizada em relação a digitar tudo sem sugestões.
  double? get keystrokeSavings => baselineInteractions == 0
      ? null
      : 1 - interactions / baselineInteractions;

  double? get keystrokeSavingsSelections =>
      baselineSelections == 0 ? null : 1 - selections / baselineSelections;

  double? get wordsPerMinute => duration == Duration.zero
      ? null
      : characters / 5 / (duration.inMilliseconds / 60000);

  double? get secondsPerInteraction =>
      _ratio(duration.inMilliseconds / 1000, interactions);

  /// Erros corrigidos / (caracteres produzidos + erros corrigidos).
  double? get correctedErrorRate =>
      _ratio(erasedCharacters, characters + erasedCharacters);

  double? get rejectedAcceptanceRate =>
      _ratio(rejectedAcceptances, acceptances);

  /// Palavras que apareceram como primeira sugestão antes de serem completadas.
  double? get predictionAccuracyTop1 => _ratio(wordsPredictedTop1, words);

  /// Palavras que apareceram entre as sugestões antes de serem completadas.
  double? get predictionAccuracy => _ratio(wordsPredicted, words);

  double? get meanCharactersBeforePrediction =>
      _ratio(charactersBeforePrediction, wordsPredicted);

  /// Palavras inseridas aceitando uma sugestão.
  double? get completionRate => _ratio(wordsAccepted, words);

  /// Das palavras previstas, quantas o usuário de fato aceitou.
  double? get suggestionUtilization => _ratio(wordsAccepted, wordsPredicted);

  void add(TypingCounts other) {
    duration += other.duration;
    characters += other.characters;
    words += other.words;
    interactions += other.interactions;
    selections += other.selections;
    gazeInteractions += other.gazeInteractions;
    touchInteractions += other.touchInteractions;
    baselineInteractions += other.baselineInteractions;
    baselineSelections += other.baselineSelections;
    backspaces += other.backspaces;
    clears += other.clears;
    erasedCharacters += other.erasedCharacters;
    acceptances += other.acceptances;
    rejectedAcceptances += other.rejectedAcceptances;
    shortcutAcceptances += other.shortcutAcceptances;
    wordsAccepted += other.wordsAccepted;
    wordsPredicted += other.wordsPredicted;
    wordsPredictedTop1 += other.wordsPredictedTop1;
    charactersBeforePrediction += other.charactersBeforePrediction;
    other.acceptedRanks.forEach((rank, count) {
      acceptedRanks[rank] = (acceptedRanks[rank] ?? 0) + count;
    });
  }

  Map<String, Object?> toJson() => {
    'durationSeconds': duration.inMilliseconds / 1000,
    'characters': characters,
    'words': words,
    'kspc': {
      'interactions': _round(kspc),
      'selections': _round(kspcSelections),
    },
    'keystrokeSavings': {
      'interactions': _round(keystrokeSavings),
      'selections': _round(keystrokeSavingsSelections),
    },
    'wordsPerMinute': _round(wordsPerMinute),
    'secondsPerInteraction': _round(secondsPerInteraction),
    'prediction': {
      'accuracyTop1': _round(predictionAccuracyTop1),
      'accuracy': _round(predictionAccuracy),
      'meanCharactersBeforePrediction': _round(meanCharactersBeforePrediction),
      'completionRate': _round(completionRate),
      'utilization': _round(suggestionUtilization),
      'acceptances': acceptances,
      'shortcutAcceptances': shortcutAcceptances,
      // Posições a partir de 1, como aparecem na tela.
      'acceptedRanks': {
        for (final rank in acceptedRanks.keys.toList()..sort())
          '${rank + 1}': acceptedRanks[rank],
      },
    },
    'errors': {
      'correctedErrorRate': _round(correctedErrorRate),
      'erasedCharacters': erasedCharacters,
      'backspaces': backspaces,
      'clears': clears,
      'rejectedAcceptances': rejectedAcceptances,
      'rejectedAcceptanceRate': _round(rejectedAcceptanceRate),
    },
    'interactions': {
      'total': interactions,
      'selections': selections,
      'gaze': gazeInteractions,
      'touch': touchInteractions,
      'baseline': baselineInteractions,
      'baselineSelections': baselineSelections,
    },
  };

  static double? _ratio(num numerator, num denominator) =>
      denominator == 0 ? null : numerator / denominator;

  static double? _round(double? value) =>
      value == null ? null : (value * 10000).round() / 10000;
}

/// Eventos entre dois FALAR.
class _Segment {
  _Segment({
    required this.startText,
    required this.position,
    required this.shown,
  }) : protectedLength = startText.length;

  /// Mensagem herdada da frase anterior.
  final String startText;

  /// Última tecla acionada antes do segmento, de onde a referência parte.
  final (int, int) position;

  /// Eventos de sugestões exibidas durante o segmento.
  final List<TypingEvent> shown;

  final acceptances = <TypingEvent>[];
  final counts = TypingCounts();
  Duration? start;

  /// Tamanho do trecho da mensagem que não foi produzido neste segmento.
  /// Apagar esse trecho é começar uma frase nova, não corrigir um erro.
  int protectedLength;

  void erase(int before, int after) {
    counts.erasedCharacters += max(0, before - max(after, protectedLength));
    protectedLength = min(protectedLength, after);
  }

  PhraseMetrics? finish(String spoken, Duration end, _Keyboard keyboard) {
    final produced = spoken.substring(protectedLength);
    final text = produced.trim();
    // Falar de novo a mesma mensagem não produz frase nova.
    if (text.isEmpty) return null;

    counts
      ..characters = text.length
      ..duration = end - start!;

    final words = _words(spoken);
    counts
      ..words = words.length
      ..wordsPredicted = words.where((w) => w.entry.predicted).length
      ..wordsPredictedTop1 = words
          .where((w) => w.entry.top1After != null)
          .length
      ..charactersBeforePrediction = words.fold(
        0,
        (sum, w) => sum + (w.entry.predictedAfter ?? 0),
      )
      ..wordsAccepted = words.where((w) => w.entry.accepted).length;

    final (interactions, selections) = keyboard.cost(
      from: position,
      text: produced.trimRight(),
      clearFirst: startText.isNotEmpty && !spoken.startsWith(startText),
    );
    counts
      ..baselineInteractions = interactions
      ..baselineSelections = selections;

    return PhraseMetrics(
      text: text,
      start: start!,
      counts: counts,
      words: [for (final w in words) w.entry],
    );
  }

  List<({WordEntry entry, int end})> _words(String spoken) {
    final words = <({WordEntry entry, int end})>[];
    for (final match in _wordPattern.allMatches(spoken)) {
      if (match.start < protectedLength) continue;
      final context = WordPredictor.normalize(spoken.substring(0, match.start));
      final word = WordPredictor.normalize(match[0]!);
      final entry = WordEntry(match[0]!);

      for (final shown in this.shown) {
        final typed = _typedLength(
          WordPredictor.normalize(shown.text!),
          context,
          word,
        );
        if (typed == null) continue;
        for (final (rank, suggestion) in shown.suggestions!.indexed) {
          if (WordPredictor.normalize(suggestion) != word) continue;
          entry.predictedAfter = min(entry.predictedAfter ?? typed, typed);
          if (rank == 0) entry.top1After = min(entry.top1After ?? typed, typed);
        }
      }
      words.add((entry: entry, end: match.end));
    }

    for (final acceptance in acceptances) {
      final accepted = WordPredictor.normalize(acceptance.text!).trimRight();
      final index = words.indexWhere(
        (w) =>
            !w.entry.accepted &&
            !w.entry.shortcut &&
            WordPredictor.normalize(spoken.substring(0, w.end)) == accepted,
      );
      if (index < 0) {
        counts.rejectedAcceptances++;
        continue;
      }
      // Sem ter aparecido antes de completa, a palavra foi digitada, não
      // prevista: a sugestão só serviu de atalho.
      if (!words[index].entry.predicted) {
        words[index].entry.shortcut = true;
        counts.shortcutAcceptances++;
        continue;
      }
      final rank = acceptance.rank!;
      words[index].entry.acceptedRank = rank;
      counts.acceptedRanks[rank] = (counts.acceptedRanks[rank] ?? 0) + 1;
    }
    return words;
  }

  /// Quantas letras de [word] já estavam digitadas quando a mensagem era
  /// [shown], ou null se [shown] não estava a caminho dessa palavra.
  static int? _typedLength(String shown, String context, String word) {
    if (shown.startsWith(context)) {
      final rest = shown.substring(context.length);
      return rest.length < word.length && word.startsWith(rest)
          ? rest.length
          : null;
    }
    // Sem espaço no fim, o preditor já trata a última palavra como completa
    // quando conhece o contexto, e aceitar a sugestão a acrescenta depois dela.
    return context.endsWith(' ') && shown == context.trimRight() ? 0 : null;
  }

  static final _wordPattern = RegExp(r'\S+');
}

/// Custo de navegação no teclado, reproduzindo as regras da tela: mudar de
/// linha limita a coluna ao tamanho da linha de destino.
class _Keyboard {
  _Keyboard(this.layout) {
    for (var r = 0; r < layout.length; r++) {
      for (var c = 0; c < layout[r].length; c++) {
        final key = layout[r][c];
        switch (key.action) {
          case KeyAction.character:
            _letters[key.label] = (r, c);
          case KeyAction.space:
            _space = (r, c);
          case KeyAction.clear:
            _clear = (r, c);
          case KeyAction.speak:
            _speak = (r, c);
          case KeyAction.backspace:
            break;
        }
      }
    }
  }

  final List<List<KeyDef>> layout;
  final _letters = <String, (int, int)>{};
  (int, int)? _space;
  (int, int)? _clear;
  (int, int)? _speak;

  /// Comandos e seleções mínimos para digitar [text] letra a letra e falar,
  /// partindo de [from]. Sem acentos nem hífen, que o teclado não tem.
  (int, int) cost({
    required (int, int) from,
    required String text,
    required bool clearFirst,
  }) {
    var position = from;
    var interactions = 0;
    var selections = 0;
    void press((int, int)? key) {
      if (key == null) return;
      interactions += _distance(position, key) + 1;
      selections++;
      position = key;
    }

    if (clearFirst) press(_clear);
    for (final char in WordPredictor.normalize(text).toUpperCase().split('')) {
      press(char == ' ' ? _space : _letters[char]);
    }
    press(_speak);
    return (interactions, selections);
  }

  int _distance((int, int) from, (int, int) to) {
    final distances = {from: 0};
    final queue = [from];
    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      if (current == to) return distances[current]!;
      for (final next in _neighbors(current)) {
        if (distances.containsKey(next)) continue;
        distances[next] = distances[current]! + 1;
        queue.add(next);
      }
    }
    throw StateError('Tecla inalcançável: $to');
  }

  Iterable<(int, int)> _neighbors((int, int) position) sync* {
    final (row, column) = position;
    for (final delta in const [-1, 1]) {
      final r = (row + delta).clamp(0, layout.length - 1);
      yield (r, column.clamp(0, layout[r].length - 1));
      yield (row, (column + delta).clamp(0, layout[row].length - 1));
    }
  }
}

int _commonPrefixLength(String a, String b) {
  final length = min(a.length, b.length);
  var i = 0;
  while (i < length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}
