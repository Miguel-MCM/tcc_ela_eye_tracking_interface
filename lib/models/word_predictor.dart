import 'dart:convert';
import 'dart:math';

import 'keyboard_layout.dart';
import 'keyboard_navigation.dart';

/// Suggests the next word using probabilities from an n-gram model.
///
/// The text is normalized (lowercase, no accents, hyphens or punctuation) so
/// that the on-screen keyboard, which has no accented keys, still matches the
/// corpus.
/// Each phrase is padded with [sentenceStart] markers, and unseen contexts
/// fall back to shorter ones with Stupid Backoff (Brants et al., 2007).
/// The corpus can be replaced with phrases collected from the user in the future.
///
/// Partial words tolerate typing errors: a word is still completed when the
/// typed letters are a small edit away from one of its prefixes, with errors
/// between neighboring keys of [layout] costing less (see [typoMaxCost]).
class WordPredictor {
  WordPredictor({
    required Iterable<String> phrases,
    this.order = 3,
    this.backoffFactor = 0.4,
    this.typoMaxCost = 1,
    this.typoMinLength = 3,
    this.typoPenalty = 0.01,
    List<List<KeyDef>> layout = kKeyboardRows,
  }) : assert(order >= 2) {
    _build(phrases);
    final navigation = KeyboardNavigation(layout);
    for (final row in layout) {
      for (final key in row.where((key) => key.isCharacter)) {
        _neighbors[key.label.toLowerCase()] = {
          for (final label in navigation.neighbors(key.label))
            label.toLowerCase(),
        };
      }
    }
  }

  final int order;

  /// Multiplier applied each time the model backs off to a shorter context.
  final double backoffFactor;

  /// Highest edit cost tolerated between the typed letters and a prefix of a
  /// suggested word; 0 turns the tolerance off. A neighboring key, an extra
  /// letter or a missing one cost 1; any other wrong key costs 2.
  final int typoMaxCost;

  /// Letters typed before errors are tolerated. With fewer, almost every word
  /// is one error away and the suggestions would lose their meaning.
  final int typoMinLength;

  /// Multiplier applied to a word's score for each unit of edit cost, so
  /// exact completions usually rank first.
  final double typoPenalty;

  /// Letters one arrow away from each letter on the keyboard.
  final Map<String, Set<String>> _neighbors = {};

  /// Marks the beginning of a phrase in the n-gram contexts.
  static const sentenceStart = '<s>';

  /// `_counts[k][context][word]`: how often `word` follows a `k`-word context.
  late final List<Map<String, Map<String, int>>> _counts;

  /// `_totals[k][context]`: how often a `k`-word context is followed by a word.
  late final List<Map<String, int>> _totals;

  /// Most frequent spelling (with accents) of each normalized word.
  final Map<String, String> _displayForms = {};

  /// Initial editable corpus, inspired by the NLTK prototype phrases.
  static const defaultPhrases = [
    'eu quero beber água',
    'eu quero beber café',
    'eu quero comer',
    'eu quero comer alguma coisa',
    'eu quero ir para casa',
    'eu quero ir ao banheiro',
    'eu estou com fome',
    'eu estou com sede',
    'eu estou cansado',
    'eu estou com dor',
    'preciso de ajuda',
    'preciso ir ao banheiro',
    'preciso beber água',
    'quero falar com minha mãe',
    'quero falar com meu pai',
  ];

  /// JSON assets with the additional phrases, each one a list of strings.
  static const phraseAssets = [
    'assets/phrases/frases_AAC_1.json',
    'assets/phrases/frases_AAC_2.json',
    'assets/phrases/frases_AAC_3.json',
    'assets/phrases/frases_AAC_4.json',
    'assets/phrases/frases_AAC_5.json',
  ];

  /// Loads the default phrases plus the ones in [phraseAssets].
  ///
  /// [load] reads an asset as text: `rootBundle.loadString` in the app, a
  /// file read in tools. Taking it as a parameter keeps this file free of
  /// Flutter imports, so the offline evaluation runs with `dart run`.
  static Future<List<String>> loadPhrases(
    Future<String> Function(String path) load,
  ) async {
    final phrases = <String>[...defaultPhrases];
    for (final path in phraseAssets) {
      final decoded = jsonDecode(await load(path)) as List<dynamic>;
      phrases.addAll(decoded.cast<String>());
    }
    return phrases;
  }

  static Future<WordPredictor> defaultModel(
    Future<String> Function(String path) load,
  ) async => WordPredictor(phrases: await loadPhrases(load));

  /// Normalized words of [text], split exactly as the model splits phrases.
  static List<String> words(String text) =>
      _tokenize(text).map(normalize).toList();

  /// Lowercases [word] and removes its accents and hyphens, so "ÁGUA" becomes
  /// "agua" and "e-mail" becomes "email".
  static String normalize(String word) {
    final buffer = StringBuffer();
    for (final rune in word.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (char != '-') buffer.write(_accentFree[char] ?? char);
    }
    return buffer.toString();
  }

  /// Returns the most likely words for the current text.
  ///
  /// When the text ends in the middle of a word, that part is used as a
  /// filter. Otherwise, the model considers the last complete words.
  List<String> suggest(String text, {int limit = 3}) =>
      predict(text, limit: limit).words;

  /// [text] after accepting [suggestion], one of the [limit] words that
  /// [suggest] returned for it: the suggestion replaces the partial last word
  /// or comes after it, in uppercase like the keyboard, followed by a space.
  ///
  /// Only the model knows which case each suggestion is; guessing from the
  /// text confuses "D" + "de" with "D" followed by the word "de".
  String accept(String text, String suggestion, {int limit = 3}) {
    final prediction = predict(text, limit: limit);
    final index = prediction.words.indexOf(suggestion);
    final kept = text.trimRight();
    final prefix = index >= 0 && prediction.completesLastWord[index]
        ? kept.replaceFirst(_lastWord, '')
        : kept.isEmpty
        ? ''
        : '$kept ';
    return '$prefix${suggestion.toUpperCase()} ';
  }

  /// Like [suggest], but also tells, for each word, whether it completes the
  /// last word of [text] (`completesLastWord[i]`) or comes after it as the
  /// next word. To insert a suggestion, use [accept].
  ({List<String> words, List<bool> completesLastWord}) predict(
    String text, {
    int limit = 3,
  }) {
    final words = WordPredictor.words(text);
    final contextSize = order - 1;
    // Highest score of each candidate word and whether it completes the
    // partial word.
    final candidates = <String, ({double score, bool completes})>{};
    void offer(String word, double score, {required bool completes}) {
      final current = candidates[word];
      if (current == null || score > current.score) {
        candidates[word] = (score: score, completes: completes);
      }
    }

    if (text.endsWith(' ') || words.isEmpty) {
      _scores(_pad(words), '').forEach((w, s) => offer(w, s, completes: false));
    } else {
      // Without a trailing space, the last word may still be a prefix. If
      // the full context was seen, it may also be complete: "eu quero"
      // already suggests "beber", but "e" can be the word "e" or the start
      // of "estou". Both readings compete on the score of the whole
      // sequence: S(c | h) for a completion c, and S(last | h) × S(n | h last)
      // for a next word n.
      final partial = words.removeLast();
      final history = _pad(words);
      final completions = _scores(history, partial);
      final asWord = [...history, partial];
      final fullContext = asWord.sublist(asWord.length - contextSize);
      if (_counts[contextSize].containsKey(_contextKey(fullContext))) {
        final wordScore = completions.remove(partial) ?? 0;
        for (final MapEntry(key: w, value: s) in _scores(asWord, '').entries) {
          offer(w, wordScore * s, completes: false);
        }
      }
      completions.forEach((w, s) => offer(w, s, completes: true));
    }

    final sorted = candidates.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.score.compareTo(a.value.score);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    final top = sorted.take(limit).toList();

    return (
      words: [for (final entry in top) _displayForms[entry.key] ?? entry.key],
      completesLastWord: [for (final entry in top) entry.value.completes],
    );
  }

  /// Stupid Backoff scores for the words that start with [partial], or are
  /// within [typoMaxCost] of starting with it.
  ///
  /// S(w | context) = count(context w) / count(context) when the sequence was
  /// seen; otherwise backoffFactor × S(w | shorter context), down to unigrams.
  /// Words matched with errors are multiplied by typoPenalty ^ cost.
  Map<String, double> _scores(List<String> history, String partial) {
    final scores = <String, double>{};
    final costs = <String, int?>{};
    var weight = 1.0;

    for (var size = order - 1; size >= 0; size--) {
      final key = _contextKey(history.sublist(history.length - size));
      final candidates = _counts[size][key];
      if (candidates != null) {
        final total = _totals[size][key]!;
        for (final MapEntry(key: word, value: count) in candidates.entries) {
          if (scores.containsKey(word)) continue;
          final cost = costs.putIfAbsent(word, () => _typoCost(partial, word));
          if (cost != null) {
            scores[word] = weight * count / total * pow(typoPenalty, cost);
          }
        }
      }
      weight *= backoffFactor;
    }
    return scores;
  }

  /// Edit cost from [typed] to the closest prefix of [word], or null if it is
  /// above [typoMaxCost].
  ///
  /// Levenshtein distance against every prefix at once: the last row of the
  /// table holds the cost to each prefix `word[:j]`, and the minimum wins.
  int? _typoCost(String typed, String word) {
    if (word.startsWith(typed)) return 0;
    if (typoMaxCost == 0 || typed.length < typoMinLength) return null;

    // previous[j]: cost from the first i - 1 typed letters to word[:j].
    var previous = List.generate(word.length + 1, (j) => j);
    for (var i = 1; i <= typed.length; i++) {
      final current = List.filled(word.length + 1, i);
      for (var j = 1; j <= word.length; j++) {
        current[j] = min(
          min(previous[j], current[j - 1]) + 1,
          previous[j - 1] + _substitutionCost(typed[i - 1], word[j - 1]),
        );
      }
      if (current.reduce(min) > typoMaxCost) return null;
      previous = current;
    }
    final cost = previous.reduce(min);
    return cost <= typoMaxCost ? cost : null;
  }

  int _substitutionCost(String typed, String expected) => typed == expected
      ? 0
      : _neighbors[expected]?.contains(typed) ?? false
      ? 1
      : 2;

  void _build(Iterable<String> phrases) {
    _counts = List.generate(order, (_) => <String, Map<String, int>>{});
    _totals = List.generate(order, (_) => <String, int>{});
    final spellings = <String, Map<String, int>>{};

    for (final phrase in phrases) {
      final words = <String>[];
      for (final spelling in _tokenize(phrase)) {
        final word = normalize(spelling);
        words.add(word);
        final counts = spellings.putIfAbsent(word, () => {});
        counts[spelling] = (counts[spelling] ?? 0) + 1;
      }

      final padded = _pad(words);
      for (var index = order - 1; index < padded.length; index++) {
        final nextWord = padded[index];
        for (var size = 0; size < order; size++) {
          final key = _contextKey(padded.sublist(index - size, index));
          final counts = _counts[size].putIfAbsent(key, () => {});
          counts[nextWord] = (counts[nextWord] ?? 0) + 1;
          _totals[size][key] = (_totals[size][key] ?? 0) + 1;
        }
      }
    }

    spellings.forEach((word, counts) {
      _displayForms[word] = counts.entries
          .reduce((best, entry) => entry.value > best.value ? entry : best)
          .key;
    });
  }

  /// Prepends the [sentenceStart] markers that fill the first contexts.
  List<String> _pad(List<String> words) => [
    for (var i = 0; i < order - 1; i++) sentenceStart,
    ...words,
  ];

  /// Splits lowercase words at punctuation, keeping hyphenated words whole
  /// because the keyboard has no hyphen key to type their parts apart.
  static List<String> _tokenize(String text) => text
      .toLowerCase()
      .split(_nonWord)
      .map((word) => word.replaceAll(_edgeHyphens, ''))
      .where((word) => word.isNotEmpty)
      .toList();

  static final _lastWord = RegExp(r'\S+$');
  static final _nonWord = RegExp(r'[^\p{L}\p{N}-]+', unicode: true);
  static final _edgeHyphens = RegExp(r'^-+|-+$');

  static const _accentFree = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  static String _contextKey(List<String> words) => words.join(' ');
}
