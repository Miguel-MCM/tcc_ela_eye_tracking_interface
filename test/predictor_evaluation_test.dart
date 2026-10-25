import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/metrics/predictor_evaluation.dart';
import 'package:tcc_ela_eye_tracking_interface/models/word_predictor.dart';

void main() {
  group('digitador simulado', () {
    test('sem sugestões úteis, digita pelo caminho mínimo da referência', () {
      // Nenhuma palavra do corpus começa com as letras de "oi".
      final typist = SimulatedTypist(WordPredictor(phrases: ['bom dia']));

      final counts = typist.type('oi')!.counts;
      expect(counts.wordsAccepted, 0);
      expect(counts.interactions, counts.baselineInteractions);
      expect(counts.keystrokeSavings, 0);
    });

    test('aceita a sugestão quando ela economiza comandos', () {
      final typist = SimulatedTypist(
        WordPredictor(phrases: ['quero beber água']),
      );

      final phrase = typist.type('quero beber água')!;
      expect(phrase.text, 'QUERO BEBER ÁGUA');
      expect(phrase.counts.wordsAccepted, greaterThan(0));
      expect(phrase.counts.keystrokeSavings, greaterThan(0));
    });

    test('sugere a primeira palavra com a mensagem vazia', () {
      final predictor = WordPredictor(phrases: ['estou com dor']);

      final phrase = SimulatedTypist(predictor).type('estou com dor')!;
      expect(phrase.words.first.predictedAfter, 0);
      expect(phrase.words.first.acceptedRank, 0);
    });

    test('ignora o que não existe no teclado', () {
      final typist = SimulatedTypist(WordPredictor(phrases: ['oi']));

      expect(typist.targetWords('Tomei 2 comprimidos, ok?'), [
        'TOMEI',
        'COMPRIMIDOS',
        'OK',
      ]);
    });
  });

  group('no corpus do app', () {
    late List<String> phrases;

    setUpAll(() async {
      phrases = await WordPredictor.loadPhrases(
        (path) => File(path).readAsString(),
      );
    });

    test('toda frase sai digitada exatamente como o alvo', () {
      final typist = SimulatedTypist(WordPredictor(phrases: phrases));

      for (final phrase in deduplicate(phrases)) {
        final typed = typist.type(phrase);
        if (typed == null) continue;
        expect(
          WordPredictor.words(typed.text).join(' ').toUpperCase(),
          typist.targetWords(phrase).join(' '),
          reason: phrase,
        );
      }
    });

    test('nenhuma palavra é aceita sem ter sido prevista', () {
      final result = crossValidate(phrases);

      expect(
        result.counts.wordsAccepted,
        lessThanOrEqualTo(result.counts.wordsPredicted),
      );
    });

    test('a validação cruzada é reprodutível com a mesma semente', () {
      final a = crossValidate(phrases, seed: 7);
      final b = crossValidate(phrases, seed: 7);

      expect(a.counts.interactions, b.counts.interactions);
      expect(a.counts.wordsPredicted, b.counts.wordsPredicted);
    });
  });

  test('frases repetidas são removidas pela forma normalizada', () {
    expect(deduplicate(['Estou com dor', 'estou com dor!', 'Estou bem']), [
      'Estou com dor',
      'Estou bem',
    ]);
  });
}
