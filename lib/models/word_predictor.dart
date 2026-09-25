/// Sugere a próxima palavra usando probabilidades de um modelo n-grama.
///
/// O modelo trigram usa as duas últimas palavras completas como contexto.
/// O corpus pode ser substituído por frases coletadas do usuário no futuro.
class WordPredictor {
  WordPredictor({required Iterable<String> phrases, this.order = 3})
    : assert(order >= 2),
      _counts = _buildCounts(phrases, order);

  final int order;
  final Map<String, Map<String, int>> _counts;

  /// Corpus inicial pequeno e editável, inspirado nas frases do protótipo NLTK.
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

  factory WordPredictor.defaultModel() {
    return WordPredictor(phrases: defaultPhrases);
  }

  /// Retorna as palavras mais prováveis para o texto atual.
  ///
  /// Quando o texto termina no meio de uma palavra, essa parte é usada como
  /// filtro. Caso contrário, o modelo considera as últimas palavras completas.
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

    // Sem espaço final, a última palavra pode ainda ser um prefixo. Primeiro
    // tentamos tratá-la como completa para que "eu quero" já sugira "beber".
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
