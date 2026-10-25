import 'dart:math';

import '../models/gaze_command.dart';
import '../models/keyboard_layout.dart';
import '../models/keyboard_navigation.dart';
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
/// O digitador conhece a frase de antemão e, por padrão, não erra: o
/// resultado é um limite superior do que as sugestões podem economizar, não
/// uma previsão do desempenho de uma pessoa. Com [errorRate] ele erra letras.
class SimulatedTypist {
  SimulatedTypist(
    this.predictor, {
    this.limit = 3,
    this.errorRate = 0,
    this.noticesErrors = true,
    this.commandDuration = const Duration(milliseconds: 1500),
    List<List<KeyDef>> layout = kKeyboardRows,
    Random? random,
  }) : _navigation = KeyboardNavigation(layout),
       _random = random ?? Random(0);

  final WordPredictor predictor;

  /// Quantas sugestões a barra mostra.
  final int limit;

  /// Probabilidade de cada letra sair trocada por uma letra vizinha na grade,
  /// como numa seta a mais ou a menos.
  final double errorRate;

  /// Se o digitador percebe um erro logo depois de cometê-lo. Se não, ele
  /// segue digitando a palavra ("BWBE…") e só nota o erro no fim dela. Nos
  /// dois casos, a cada passo ele faz o que custar menos: aceitar a sugestão
  /// certa, se ela aparecer, ou apagar até o erro e redigitar.
  final bool noticesErrors;

  /// Tempo de cada comando; com o dwell padrão do rastreador, 1,5 s. Só afeta
  /// o WPM, que por isso é uma estimativa e não uma medida.
  final Duration commandDuration;

  final KeyboardNavigation _navigation;
  final Random _random;

  List<List<KeyDef>> get _layout => _navigation.layout;

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
  KeyboardNavigation get _navigation => typist._navigation;

  List<String> get _suggestions =>
      typist.predictor.suggest(_text, limit: typist.limit);

  /// Digita a última palavra de [expected] (as palavras da frase até a
  /// atual), aceitando uma sugestão assim que ela custar no máximo o mesmo
  /// que terminar a palavra à mão.
  void typeWord(List<String> expected, {required bool last}) {
    final word = expected.last;
    // Letras desta palavra já na mensagem, certas ou não.
    var typed = '';
    var erasing = false;
    while (true) {
      var correct = 0;
      while (correct < typed.length && typed[correct] == word[correct]) {
        correct++;
      }
      final wrong = typed.length - correct;

      // Com a palavra pronta, aceitá-la seria só um atalho; o digitador não usa.
      final rank = typed == word ? -1 : _rankOf(expected);
      final typingCost = _typingCost([
        for (var i = 0; i < wrong; i++) 'APAGAR',
        ...word.substring(correct).split(''),
        if (!last) ' ',
      ]);
      if (rank >= 0 && _acceptCost(rank) <= typingCost) {
        _accept(rank);
        return;
      }
      // Percebido o erro, apaga até ele.
      erasing =
          wrong > 0 &&
          (erasing || typist.noticesErrors || typed.length >= word.length);
      if (erasing) {
        pressLabel('APAGAR');
        typed = typed.substring(0, typed.length - 1);
        continue;
      }
      if (typed == word) {
        if (!last) pressLabel('ESPAÇO');
        return;
      }
      final letter = _slip(word[typed.length]) ?? word[typed.length];
      pressLabel(letter);
      typed += letter;
    }
  }

  /// Posição da sugestão que deixa na mensagem exatamente as palavras
  /// [expected], ou -1. Sem espaço no fim, o modelo também sugere a próxima
  /// palavra, então não basta a sugestão ser igual à palavra atual.
  int _rankOf(List<String> expected) => _suggestions.indexWhere(
    (s) =>
        WordPredictor.normalize(s).toUpperCase() == expected.last &&
        _sameList(
          _words(typist.predictor.accept(_text, s, limit: typist.limit)),
          expected,
        ),
  );

  /// Com probabilidade errorRate, uma letra vizinha de [letter] na grade.
  String? _slip(String letter) {
    if (typist.errorRate == 0 ||
        typist._random.nextDouble() >= typist.errorRate) {
      return null;
    }
    final options = [
      for (final label in _navigation.neighbors(letter))
        if (_isLetter(label)) label,
    ];
    return options[typist._random.nextInt(options.length)];
  }

  bool _isLetter(String label) {
    final (row, column) = _navigation.find(label);
    return _layout[row][column].isCharacter;
  }

  void pressLabel(String label) {
    final (row, column) = _navigation.find(label);
    for (final command in _navigation.path((_row, _column), (row, column))) {
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
    final suggestion = _suggestions[rank];
    _command(GazeCommand.select);

    _text = typist.predictor.accept(_text, suggestion, limit: typist.limit);
    _selectedSuggestion = null;
    events.add(
      TypingEvent.acceptance(
        _time,
        suggestion: suggestion,
        rank: rank,
        text: _text,
      ),
    );
    _recordSuggestions();
  }

  static List<String> _words(String text) => [
    for (final w in WordPredictor.words(text)) w.toUpperCase(),
  ];

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
      final key = _navigation.find(label == ' ' ? 'ESPAÇO' : label);
      cost += _navigation.path(position, key).length + 1;
      position = key;
    }
    return cost;
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);
}

/// Resultado de uma avaliação sobre um conjunto de frases.
class EvaluationResult {
  /// Contagens somadas de todas as frases (micro-média, como em
  /// [TypingMetrics.summary]).
  final counts = TypingCounts();
  var phrases = 0;
  var words = 0;

  /// Palavras de teste que não aparecem no corpus de treino: nenhuma
  /// sugestão consegue acertá-las.
  var outOfVocabulary = 0;

  double get outOfVocabularyRate => words == 0 ? 0 : outOfVocabulary / words;

  /// Treina um modelo com [train] e digita cada frase de [test] com ele.
  void _add(
    List<String> train,
    List<String> test,
    WordPredictor Function(List<String> train)? model,
    SimulatedTypist Function(WordPredictor predictor)? typist,
  ) {
    final predictor = model?.call(train) ?? WordPredictor(phrases: train);
    final simulator = typist?.call(predictor) ?? SimulatedTypist(predictor);
    final vocabulary = {for (final p in train) ...WordPredictor.words(p)};
    for (final phrase in test) {
      final metrics = simulator.type(phrase);
      if (metrics == null) continue;
      counts.add(metrics.counts);
      phrases++;
      for (final word in WordPredictor.words(phrase)) {
        words++;
        if (!vocabulary.contains(word)) outOfVocabulary++;
      }
    }
  }
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
  WordPredictor Function(List<String> train)? model,
  SimulatedTypist Function(WordPredictor predictor)? typist,
}) {
  final unique = deduplicate(phrases)..shuffle(Random(seed));
  final result = EvaluationResult();
  for (var fold = 0; fold < folds; fold++) {
    result._add(
      [
        for (final (i, p) in unique.indexed)
          if (i % folds != fold) p,
      ],
      [
        for (final (i, p) in unique.indexed)
          if (i % folds == fold) p,
      ],
      model,
      typist,
    );
  }
  return result;
}

/// Avalia nas próprias frases de treino. Serve só de referência: a diferença
/// para [crossValidate] mostra quanto o modelo depende de já ter visto a frase.
EvaluationResult evaluateInSample(
  List<String> phrases, {
  WordPredictor Function(List<String> train)? model,
  SimulatedTypist Function(WordPredictor predictor)? typist,
}) {
  final unique = deduplicate(phrases);
  return EvaluationResult().._add(unique, unique, model, typist);
}

/// Remove frases repetidas, comparando a forma normalizada.
List<String> deduplicate(List<String> phrases) {
  final seen = <String>{};
  return phrases.where((phrase) {
    final words = WordPredictor.words(phrase);
    return words.isNotEmpty && seen.add(words.join(' '));
  }).toList();
}
