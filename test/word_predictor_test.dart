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

  group('tolerância a erros de digitação', () {
    final predictor = WordPredictor(
      phrases: ['eu quero beber água', 'eu quero bem', 'estou com fome'],
    );

    test('completa a palavra com uma tecla vizinha errada', () {
      // W é vizinha de E no teclado.
      expect(predictor.suggest('EU QUERO BWB'), ['beber']);
      expect(predictor.suggest('ESTOU COM FOMW'), ['fome']);
    });

    test('tolera uma letra a mais ou a menos', () {
      expect(predictor.suggest('EU QUERO BEEB'), contains('beber'));
      expect(predictor.suggest('EU QUERO BBER'), contains('beber'));
    });

    test('não tolera tecla distante nem dois erros', () {
      // P fica longe de E.
      expect(predictor.suggest('EU QUERO BPB'), isEmpty);
      expect(predictor.suggest('EU QUERO BWBWR'), isEmpty);
    });

    test('só tolera erros a partir de typoMinLength letras', () {
      expect(predictor.suggest('EU QUERO BW'), isEmpty);
    });

    test('a completação exata vem antes da com erro', () {
      // Com "BEB", "bem" está a um erro (o B a mais); com "BEM", é "beber"
      // que está a um erro (o M a mais).
      expect(predictor.suggest('EU QUERO BEB').first, 'beber');
      expect(predictor.suggest('EU QUERO BEM').first, 'bem');
    });

    test('typoMaxCost 0 desliga a tolerância', () {
      final exact = WordPredictor(
        phrases: ['eu quero beber água'],
        typoMaxCost: 0,
      );
      expect(exact.suggest('EU QUERO BWB'), isEmpty);
    });

    test('accept substitui a palavra com erro', () {
      expect(predictor.accept('EU QUERO BWB', 'beber'), 'EU QUERO BEBER ');
    });
  });

  group('predict', () {
    final predictor = WordPredictor(
      phrases: ['eu quero dormir', 'preciso de ajuda', 'gosto de café'],
    );

    test('palavra pela metade é completada', () {
      final prediction = predictor.predict('EU QUERO D');

      expect(prediction.completesLastWord, [true, true]);
      expect(prediction.words, ['dormir', 'de']);
    });

    test('contexto conhecido sem espaço sugere a próxima palavra', () {
      final prediction = predictor.predict('EU QUERO');

      expect(prediction.completesLastWord.first, isFalse);
      expect(prediction.words.first, 'dormir');
    });

    test('accept completa a palavra pela metade ou acrescenta a próxima', () {
      expect(predictor.accept('EU QUERO D', 'de'), 'EU QUERO DE ');
      expect(predictor.accept('EU QUERO', 'dormir'), 'EU QUERO DORMIR ');
      expect(predictor.accept('EU QUERO D ', 'de'), 'EU QUERO D DE ');
      expect(predictor.accept('', 'eu'), 'EU ');
    });

    test('depois de um espaço sugere a próxima palavra', () {
      expect(
        predictor.predict('EU QUERO D ').completesLastWord,
        everyElement(isFalse),
      );
    });

    test('letra que também é palavra mistura completações e próximas '
        'palavras', () {
      final predictor = WordPredictor(
        phrases: [
          'estou com fome',
          'estou cansado',
          'eu quero água',
          'eu quero comer',
          'e depois',
        ],
      );

      final prediction = predictor.predict('E');
      // "estou" e "eu" completam o "E"; "depois" vem depois da palavra "e".
      expect(prediction.words, ['estou', 'eu', 'depois']);
      expect(prediction.completesLastWord, [true, true, false]);
    });

    test('a própria letra não é sugerida como completação de si mesma', () {
      final predictor = WordPredictor(phrases: ['e depois', 'eu quero']);

      // Aceitar "e" como completação de "E" só acrescentaria um espaço; a
      // palavra "e" já está coberta pelas próximas palavras.
      final prediction = predictor.predict('E', limit: 10);
      for (final (i, word) in prediction.words.indexed) {
        if (word == 'e') expect(prediction.completesLastWord[i], isFalse);
      }
    });
  });
}
