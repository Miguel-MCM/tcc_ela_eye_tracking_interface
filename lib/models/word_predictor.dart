import 'dart:convert';

import 'package:flutter/services.dart';

/// Suggests the next word using probabilities from an n-gram model.
///
/// The trigram model uses the two last complete words as context.
/// The corpus can be replaced with phrases collected from the user in the future.
class WordPredictor {
  WordPredictor({required Iterable<String> phrases, this.order = 3})
    : assert(order >= 2),
      _counts = _buildCounts(phrases, order);

  final int order;
  final Map<String, Map<String, int>> _counts;

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

  /// Loads the default phrases and the additional phrases from JSON assets.
  static Future<WordPredictor> defaultModel() async {
    final phrases = <String>[...defaultPhrases];

    for (var index = 1; index <= 5; index++) {
      final path = 'assets/phrases/frases_AAC_$index.json';
      final content = await rootBundle.loadString(path);
      final decoded = jsonDecode(content) as List<dynamic>;

      phrases.addAll(decoded.cast<String>());
    }

    return WordPredictor(phrases: phrases);
  }

  /// Returns the most likely words for the current text.
  ///
  /// When the text ends in the middle of a word, that part is used as a
  /// filter. Otherwise, the model considers the last complete words.
  List<String> suggest(String text, {int limit = 3}) {
    final normalized = text.trim().toLowerCase();
    final words = normalized.isEmpty
        ? <String>[]
        : normalized.split(RegExp(r'\s+'));
    final contextSize = order - 1;
    final fullContext = words.length > contextSize
        ? words.sublist(words.length - contextSize)
        : words;
    var partial = '';
    var context = fullContext;
    var candidates = _counts[_contextKey(context)] ?? const <String, int>{};

    // Without a trailing space, the last word may still be a prefix. First
    // try treating it as complete so that "eu quero" already suggests "beber".
    if (candidates.isEmpty && !text.endsWith(' ') && words.isNotEmpty) {
      partial = words.removeLast();
      context = words.length > contextSize
          ? words.sublist(words.length - contextSize)
          : words;
      candidates = _counts[_contextKey(context)] ?? const <String, int>{};
    }

    final sorted =
        candidates.entries
            .where((entry) => entry.key.startsWith(partial))
            .toList()
          ..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            return byCount != 0 ? byCount : a.key.compareTo(b.key);
          });

    return sorted.take(limit).map((entry) => entry.key).toList();
  }

  static Map<String, Map<String, int>> _buildCounts(
    Iterable<String> phrases,
    int order,
  ) {
    final counts = <String, Map<String, int>>{};
    final contextSize = order - 1;

    for (final phrase in phrases) {
      final words = phrase
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      for (var index = 0; index < words.length; index++) {
        final start = index - contextSize;
        final context = words.sublist(start < 0 ? 0 : start, index);
        final key = _contextKey(context);
        final nextWord = words[index];
        counts.putIfAbsent(key, () => {})[nextWord] =
            (counts[key]![nextWord] ?? 0) + 1;
      }
    }
    return counts;
  }

  static String _contextKey(List<String> words) => words.join(' ');
}
