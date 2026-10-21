import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/models/word_predictor.dart';

void main() {
  group('normalização', () {
    test('remove acentos e coloca em minúsculas', () {
      expect(WordPredictor.normalize('ÁGUA'), 'agua');
      expect(WordPredictor.normalize('Posição'), 'posicao');
    });

    test('texto digitado sem acento casa com o corpus acentuado', () {
      final predictor = WordPredictor(phrases: ['preciso beber água']);

      expect(predictor.suggest('PRECISO BEBER ').first, 'água');
      expect(predictor.suggest('PRECISO BEBER AG'), ['água']);
    });

    test('usa a grafia mais frequente na sugestão', () {
      final predictor = WordPredictor(
        phrases: ['quero café', 'quero café', 'quero cafe'],
      );

      expect(predictor.suggest('QUERO ').first, 'café');
    });

    test('ignora pontuação e mantém palavras com hífen inteiras', () {
      final predictor = WordPredictor(
        phrases: ['Você pode ligar o ar-condicionado?', 'Envie um e-mail'],
      );

      expect(predictor.suggest('LIGAR O ').first, 'ar-condicionado');
      expect(predictor.suggest('LIGAR O AR'), ['ar-condicionado']);
      // "e-mail" não pode virar a palavra "e" no início de uma frase.
      expect(predictor.suggest('E'), ['envie', 'e-mail']);
    });
  });

  group('<s>', () {
    test('sugere palavras que começam frases quando o texto está vazio', () {
      final predictor = WordPredictor(
        phrases: ['eu quero água', 'eu preciso de ajuda', 'quero comer'],
      );

      expect(predictor.suggest('').first, 'eu');
    });

    test('distingue início de frase de uma palavra no meio', () {
      final predictor = WordPredictor(
        phrases: ['ajuda por favor', 'preciso de ajuda médica'],
      );

      expect(predictor.suggest('AJUDA ').first, 'por');
      expect(predictor.suggest('DE AJUDA ').first, 'médica');
    });
  });

  group('Stupid Backoff', () {
    test('recua para contextos menores quando o contexto não foi visto', () {
      final predictor = WordPredictor(phrases: WordPredictor.defaultPhrases);

      // "agora eu quero" nunca aparece no corpus, mas "eu quero" sim.
      expect(predictor.suggest('AGORA EU QUERO '), contains('beber'));
    });

    test('contexto mais longo pesa mais que o recuo', () {
      final predictor = WordPredictor(
        phrases: [
          'eu quero comer',
          'ele quer dormir',
          'ele quer dormir',
          'ele quer dormir',
        ],
      );

      // "comer" vem do trigrama completo; "dormir" só do unigrama.
      expect(predictor.suggest('EU QUERO ').first, 'comer');
    });

    test('ainda sugere palavras para um contexto desconhecido', () {
      final predictor = WordPredictor(phrases: WordPredictor.defaultPhrases);

      expect(predictor.suggest('XYZ '), isNotEmpty);
      expect(predictor.suggest('XYZ BAN'), ['banheiro']);
    });
  });

  group('predict', () {
    final predictor = WordPredictor(
      phrases: ['eu quero dormir', 'preciso de ajuda', 'gosto de café'],
    );

    test('palavra pela metade é completada', () {
      final prediction = predictor.predict('EU QUERO D');

      expect(prediction.completesLastWord, isTrue);
      expect(prediction.words, ['dormir', 'de']);
    });

    test('contexto conhecido sem espaço sugere a próxima palavra', () {
      final prediction = predictor.predict('EU QUERO');

      expect(prediction.completesLastWord, isFalse);
      expect(prediction.words.first, 'dormir');
    });

    test('depois de um espaço sugere a próxima palavra', () {
      expect(predictor.predict('EU QUERO D ').completesLastWord, isFalse);
    });
  });
}
