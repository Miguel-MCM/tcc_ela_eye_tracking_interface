import 'dart:math';

import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';
import '../models/word_predictor.dart';
import 'typing_event.dart';
import 'typing_metrics.dart';

/// Avaliação offline do [WordPredictor], sem usuários.
///
/// Um digitador simulado escreve frases do corpus seguindo as mesmas regras
/// de navegação de CommunicatorScreen, e os eventos gerados passam pelo mesmo
/// [TypingMetrics] das sessões reais. Assim a simulação e os testes com
/// usuários medem exatamente as mesmas coisas.
///
/// O digitador conhece a frase de antemão e não erra: o resultado é um limite
/// superior do que as sugestões podem economizar, não uma previsão do
/// desempenho de uma pessoa.
class SimulatedTypist {
  SimulatedTypist(
    this.predictor, {
    this.limit = 3,
    this.showSuggestionsWhenEmpty = false,
    this.commandDuration = const Duration(milliseconds: 1500),
    List<List<KeyDef>> layout = kKeyboardRows,
  }) : _layout = layout;

  final WordPredictor predictor;

  /// Quantas sugestões a barra mostra.
  final int limit;

  /// A tela atual esconde as sugestões com a mensagem vazia, então a primeira
  /// palavra de cada frase nunca é prevista. Ligar isto simula a alternativa.
  final bool showSuggestionsWhenEmpty;

  /// Tempo de cada comando; com o dwell padrão do rastreador, 1,5 s. Só afeta
  /// o WPM, que por isso é uma estimativa e não uma medida.
  final Duration commandDuration;

  final List<List<KeyDef>> _layout;

  /// Digita [phrase] a partir de uma mensagem vazia, com o foco na primeira
  /// tecla, e termina em FALAR. Devolve null se não sobrar nada digitável.
  PhraseMetrics? type(String phrase) {
    final words = targetWords(phrase);
    if (words.isEmpty) return null;
    final session = _Session(this);
    for (var i = 0; i < words.length; i++) {
      session.typeWord(words.sublist(0, i + 1), last: i == words.length - 1);
    }
    session.pressLabel('FALAR');
    final metrics = TypingMetrics.fromEvents(session.events, layout: _layout);
    return metrics.phrases.single;
  }

  /// Palavras de [phrase] como o teclado consegue digitá-las: sem acentos,
  /// em maiúsculas e só com as letras que existem nas teclas.
  List<String> targetWords(String phrase) {
    final letters = {
      for (final row in _layout)
        for (final key in row)
          if (key.isCharacter) key.label,
    };
    return [
      for (final word in WordPredictor.words(phrase))
        word.toUpperCase().split('').where(letters.contains).join(),
    ].where((word) => word.isNotEmpty).toList();
  }
}

/// Estado da tela durante uma frase simulada: espelha os campos e as regras
/// de CommunicatorScreen (_moveRow, _moveColumn, _pressKey e
/// _acceptSuggestion).
class _Session {
  _Session(this.typist) {
    _recordSuggestions();
  }

  final SimulatedTypist typist;
  final events = <TypingEvent>[];
  var _text = '';
  var _row = 0;
  var _column = 0;
  int? _selectedSuggestion;
  var _time = Duration.zero;
  TypingEvent? _lastSuggestions;

  List<List<KeyDef>> get _layout => typist._layout;

  List<String> get _suggestions =>
      _text.isEmpty && !typist.showSuggestionsWhenEmpty
      ? const []
      : typist.predictor.suggest(_text, limit: typist.limit);

  /// Digita a última palavra de [expected] letra a letra, aceitando uma
  /// sugestão assim que ela custar no máximo o mesmo que terminar a palavra
  /// à mão. [expected] traz as palavras da frase até a atual, para conferir
  /// o texto que a sugestão produziria: com a palavra completa e sem espaço,
  /// o modelo pode estar sugerindo a próxima palavra, e não a atual.
  void typeWord(List<String> expected, {required bool last}) {
    final word = expected.last;
    var typed = 0;
    while (true) {
      // Com a palavra inteira já digitada, aceitar a sugestão igual a ela só
      // serviria de atalho para o espaço. TypingMetrics não conta isso como
      // previsão, então o digitador não faz para manter as métricas coerentes.
      final suggestions = typed < word.length ? _suggestions : const <String>[];
      final rank = suggestions.indexWhere(
        (s) =>
            WordPredictor.normalize(s).toUpperCase() == word &&
            _sameList(_words(_textAfterAccepting(s)), expected),
      );
      final rest = word.substring(typed).split('');
      final typingCost = _typingCost([...rest, if (!last) ' ']);
      if (rank >= 0 && _acceptCost(rank) <= typingCost) {
        _accept(rank);
        return;
      }
      if (typed == word.length) {
        if (!last) pressLabel('ESPAÇO');
        return;
      }
      pressLabel(word[typed]);
      typed++;
    }
  }

  void pressLabel(String label) {
    final (row, column) = _find(label);
    for (final command in _path((_row, _column), (row, column))) {
      _command(command);
    }
    _command(GazeCommand.select);
    final key = _layout[row][column];
    switch (key.action) {
      case KeyAction.character:
        _text += key.label;
      case KeyAction.space:
        if (_text.isNotEmpty && !_text.endsWith(' ')) _text += ' ';
      case KeyAction.backspace:
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      case KeyAction.clear:
        _text = '';
      case KeyAction.speak:
        break;
    }
    events.add(
      TypingEvent.key(
        _time,
        action: key.action,
        label: key.label,
        row: row,
        column: column,
        text: _text,
      ),
    );
    _recordSuggestions();
  }

  /// Sobe até a primeira linha, entra na barra, anda até a sugestão e seleciona.
  void _accept(int rank) {
    while (_row > 0) {
      _command(GazeCommand.up);
    }
    _command(GazeCommand.up);
    for (var i = 0; i < rank; i++) {
      _command(GazeCommand.right);
    }
    final suggestion = _suggestions[_selectedSuggestion!];
    _command(GazeCommand.select);

    final prediction = typist.predictor.predict(_text, limit: typist.limit);
    _text = _textAfterAccepting(suggestion);
    _selectedSuggestion = null;
    events.add(
      TypingEvent.acceptance(
        _time,
        suggestion: suggestion,
        rank: prediction.words.indexOf(suggestion),
        text: _text,
      ),
    );
    _recordSuggestions();
  }

  /// A mensagem depois de aceitar [suggestion], como em _acceptSuggestion.
  String _textAfterAccepting(String suggestion) {
    final prediction = typist.predictor.predict(_text, limit: typist.limit);
    final kept = _text.trimRight();
    final prefix = prediction.completesLastWord
        ? kept.replaceFirst(_lastWord, '')
        : kept.isEmpty
        ? ''
        : '$kept ';
    return '$prefix${suggestion.toUpperCase()} ';
  }

  static List<String> _words(String text) =>
      [for (final w in WordPredictor.words(text)) w.toUpperCase()];

  void _command(GazeCommand command) {
    _time += typist.commandDuration;
    events.add(TypingEvent.command(_time, command, InputSource.gaze));
    switch (command) {
      case GazeCommand.up || GazeCommand.down:
        final delta = command == GazeCommand.up ? -1 : 1;
        if (_selectedSuggestion != null) {
          if (delta > 0) _selectedSuggestion = null;
        } else if (delta < 0 && _row == 0 && _suggestions.isNotEmpty) {
          _selectedSuggestion = 0;
        } else {
          _row = (_row + delta).clamp(0, _layout.length - 1);
          _column = _column.clamp(0, _layout[_row].length - 1);
        }
      case GazeCommand.left || GazeCommand.right:
        final delta = command == GazeCommand.left ? -1 : 1;
        final selected = _selectedSuggestion;
        if (selected != null) {
          _selectedSuggestion = (selected + delta).clamp(
            0,
            _suggestions.length - 1,
          );
        } else {
          _column = (_column + delta).clamp(0, _layout[_row].length - 1);
        }
      case GazeCommand.select:
        break;
    }
  }

  /// Registra as sugestões só quando mudam, como TypingMetricsRecorder.
  void _recordSuggestions() {
    final suggestions = _suggestions;
    final last = _lastSuggestions;
    if (last != null &&
        last.text == _text &&
        _sameList(last.suggestions!, suggestions)) {
      return;
    }
    _lastSuggestions = TypingEvent.suggestions(
      _time,
      text: _text,
      suggestions: suggestions,
    );
    events.add(_lastSuggestions!);
  }

  /// Comandos para aceitar a sugestão [rank] a partir da posição atual.
  int _acceptCost(int rank) => _row + 1 + rank + 1;

  /// Comandos para digitar [labels] (letras ou ' ') a partir da posição atual.
  int _typingCost(List<String> labels) {
    var position = (_row, _column);
    var cost = 0;
    for (final label in labels) {
      final key = _find(label == ' ' ? 'ESPAÇO' : label);
      cost += _path(position, key).length + 1;
      position = key;
    }
    return cost;
  }

  (int, int) _find(String label) {
    for (var r = 0; r < _layout.length; r++) {
      for (var c = 0; c < _layout[r].length; c++) {
        if (_layout[r][c].label == label) return (r, c);
      }
    }
    throw ArgumentError('Tecla inexistente: $label');
  }

  /// Caminho mínimo de setas entre duas teclas, com as mesmas regras de
  /// _Keyboard em typing_metrics.dart: mudar de linha limita a coluna.
  List<GazeCommand> _path((int, int) from, (int, int) to) {
    final previous = <(int, int), ((int, int), GazeCommand)?>{from: null};
    final queue = [from];
    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      if (current == to) break;
      final (row, column) = current;
      for (final (command, dr, dc) in const [
        (GazeCommand.up, -1, 0),
        (GazeCommand.down, 1, 0),
        (GazeCommand.left, 0, -1),
        (GazeCommand.right, 0, 1),
      ]) {
        final r = (row + dr).clamp(0, _layout.length - 1);
        final next = (r, (column + dc).clamp(0, _layout[r].length - 1));
        if (previous.containsKey(next)) continue;
        previous[next] = (current, command);
        queue.add(next);
      }
    }
    final path = <GazeCommand>[];
    for (var step = previous[to]; step != null; step = previous[step.$1]) {
      path.add(step.$2);
    }
    return path.reversed.toList();
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);

  static final _lastWord = RegExp(r'\S+$');
}

/// Resultado de uma avaliação sobre um conjunto de frases.
class EvaluationResult {
  EvaluationResult({
    required this.counts,
    required this.phrases,
    required this.words,
    required this.outOfVocabulary,
  });

  /// Contagens somadas de todas as frases (micro-média, como em
  /// [TypingMetrics.summary]).
  final TypingCounts counts;
  final int phrases;
  final int words;

  /// Palavras de teste que não aparecem no corpus de treino: nenhuma
  /// sugestão consegue acertá-las.
  final int outOfVocabulary;

  double get outOfVocabularyRate => words == 0 ? 0 : outOfVocabulary / words;
}

/// Validação cruzada em [folds] partes: cada frase é digitada por um modelo
/// treinado sem ela.
///
/// As frases são deduplicadas pela forma normalizada antes da divisão, para
/// que a mesma frase não caia no treino e no teste ao mesmo tempo, e
/// embaralhadas com [seed] para que o resultado seja reprodutível.
EvaluationResult crossValidate(
  List<String> phrases, {
  int folds = 10,
  int seed = 42,
  SimulatedTypist Function(WordPredictor predictor)? typist,
}) {
  final unique = deduplicate(phrases)..shuffle(Random(seed));
  final counts = TypingCounts();
  var words = 0;
  var outOfVocabulary = 0;
  var typed = 0;

  for (var fold = 0; fold < folds; fold++) {
    final train = <String>[];
    final test = <String>[];
    for (var i = 0; i < unique.length; i++) {
      (i % folds == fold ? test : train).add(unique[i]);
    }
    final vocabulary = {for (final p in train) ...WordPredictor.words(p)};
    final predictor = WordPredictor(phrases: train);
    final simulator = typist?.call(predictor) ?? SimulatedTypist(predictor);

    for (final phrase in test) {
      final metrics = simulator.type(phrase);
      if (metrics == null) continue;
      counts.add(metrics.counts);
      typed++;
      for (final word in WordPredictor.words(phrase)) {
        words++;
        if (!vocabulary.contains(word)) outOfVocabulary++;
      }
    }
  }
  return EvaluationResult(
    counts: counts,
    phrases: typed,
    words: words,
    outOfVocabulary: outOfVocabulary,
  );
}

/// Avalia nas próprias frases de treino. Serve só de referência: a diferença
/// para [crossValidate] mostra quanto o modelo depende de já ter visto a frase.
EvaluationResult evaluateInSample(
  List<String> phrases, {
  SimulatedTypist Function(WordPredictor predictor)? typist,
}) {
  final unique = deduplicate(phrases);
  final predictor = WordPredictor(phrases: unique);
  final simulator = typist?.call(predictor) ?? SimulatedTypist(predictor);
  final counts = TypingCounts();
  var words = 0;
  var typed = 0;
  for (final phrase in unique) {
    final metrics = simulator.type(phrase);
    if (metrics == null) continue;
    counts.add(metrics.counts);
    typed++;
    words += WordPredictor.words(phrase).length;
  }
  return EvaluationResult(
    counts: counts,
    phrases: typed,
    words: words,
    outOfVocabulary: 0,
  );
}

/// Remove frases repetidas, comparando a forma normalizada.
List<String> deduplicate(List<String> phrases) {
  final seen = <String>{};
  return [
    for (final phrase in phrases)
      if (WordPredictor.words(phrase).isNotEmpty &&
          seen.add(WordPredictor.words(phrase).join(' ')))
        phrase,
  ];
}
