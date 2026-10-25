import 'dart:convert';

/// Suggests the next word using probabilities from an n-gram model.
///
/// The text is normalized (lowercase, no accents, hyphens or punctuation) so
/// that the on-screen keyboard, which has no accented keys, still matches the
/// corpus.
/// Each phrase is padded with [sentenceStart] markers, and unseen contexts
/// fall back to shorter ones with Stupid Backoff (Brants et al., 2007).
/// The corpus can be replaced with phrases collected from the user in the future.
class WordPredictor {
  WordPredictor({
    required Iterable<String> phrases,
    this.order = 3,
    this.backoffFactor = 0.4,
  }) : assert(order >= 2) {
    _build(phrases);
  }

  final int order;

  /// Multiplier applied each time the model backs off to a shorter context.
  final double backoffFactor;

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

  /// Like [suggest], but also tells whether the words complete the last word
  /// of [text] (`completesLastWord`) or come after it as the next word.
  ///
  /// Only the model knows which case it chose, so whoever inserts a
  /// suggestion must ask here instead of guessing from the text.
  ({List<String> words, bool completesLastWord}) predict(
    String text, {
    int limit = 3,
  }) {
    final words = _tokenize(text).map(normalize).toList();
    final contextSize = order - 1;
    var history = _pad(words);
    var partial = '';

    // Without a trailing space, the last word may still be a prefix. Treat it
    // as complete only if the full context was seen, so that "eu quero"
    // already suggests "beber" while "eu quero b" completes to "beber".
    if (!text.endsWith(' ') && words.isNotEmpty) {
      final fullContext = history.sublist(history.length - contextSize);
      if (!_counts[contextSize].containsKey(_contextKey(fullContext))) {
        partial = words.removeLast();
        history = _pad(words);
      }
    }

    final sorted = _scores(history, partial).entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });

    return (
      words: sorted
          .take(limit)
          .map((entry) => _displayForms[entry.key] ?? entry.key)
          .toList(),
      completesLastWord: partial.isNotEmpty,
    );
  }

  /// Stupid Backoff scores for the words that start with [partial].
  ///
  /// S(w | context) = count(context w) / count(context) when the sequence was
  /// seen; otherwise backoffFactor × S(w | shorter context), down to unigrams.
  Map<String, double> _scores(List<String> history, String partial) {
    final scores = <String, double>{};
    var weight = 1.0;

    for (var size = order - 1; size >= 0; size--) {
      final key = _contextKey(history.sublist(history.length - size));
      final candidates = _counts[size][key];
      if (candidates != null) {
        final total = _totals[size][key]!;
        for (final entry in candidates.entries) {
          if (entry.key.startsWith(partial)) {
            scores.putIfAbsent(entry.key, () => weight * entry.value / total);
          }
        }
      }
      weight *= backoffFactor;
    }
    return scores;
  }

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
