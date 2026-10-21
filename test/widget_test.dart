import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tcc_ela_eye_tracking_interface/main.dart';
import 'package:tcc_ela_eye_tracking_interface/models/control_style.dart';
import 'package:tcc_ela_eye_tracking_interface/models/word_predictor.dart';
import 'package:tcc_ela_eye_tracking_interface/screens/communicator_screen.dart';
import 'package:tcc_ela_eye_tracking_interface/tts/speech_synthesizer.dart';
import 'package:tcc_ela_eye_tracking_interface/widgets/message_bar.dart';

/// Texto atualmente na faixa de mensagem (ignora as teclas de mesmo rótulo).
Finder messageText(String text) =>
    find.descendant(of: find.byType(MessageBar), matching: find.text(text));

class _FakeSpeechSynthesizer implements SpeechSynthesizer {
  final ValueNotifier<SpeechSynthesizerState> notifier = ValueNotifier(
    SpeechSynthesizerState.idle,
  );
  final spoken = <String>[];

  @override
  ValueListenable<SpeechSynthesizerState> get state => notifier;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    notifier.value = SpeechSynthesizerState.disposed;
  }
}

void main() {
  // A câmera não existe no ambiente de teste; CameraView cai no estado de erro
  // e o resto da tela segue funcionando, que é o que interessa aqui.

  // Os dois arranjos de controle compartilham o mesmo GazeButton e o mesmo
  // _handleCommand, então a navegação tem que se comportar igual nos dois.
  for (final style in ControlStyle.values) {
    group('controles em ${style.name}', () {
      Future<void> pump(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: CommunicatorScreen(controlStyle: style)),
        );
        await tester.pump();
      }

      testWidgets('começa com a mensagem vazia', (tester) async {
        await pump(tester);
        expect(messageText('Sua mensagem aparece aqui'), findsOneWidget);
      });

      testWidgets('confirmar digita a tecla destacada', (tester) async {
        await pump(tester);

        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();

        expect(messageText('Q'), findsOneWidget);
      });

      testWidgets('as setas movem o destaque antes de confirmar', (
        tester,
      ) async {
        await pump(tester);

        await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();

        expect(messageText('W'), findsOneWidget);
      });

      testWidgets('a coluna é limitada ao mudar para uma linha mais curta', (
        tester,
      ) async {
        await pump(tester);

        // Última coluna da primeira linha (P), depois desce para a linha
        // final, que só tem quatro teclas.
        for (var i = 0; i < 9; i++) {
          await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
          await tester.pump();
        }
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
          await tester.pump();
        }
        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();

        // Sem o clamp isto estouraria o índice da linha de teclas especiais.
        expect(messageText('LIMPAR'), findsNothing);
      });

      testWidgets('apagar remove o último caractere', (tester) async {
        await pump(tester);

        await tester.tap(find.text('O'));
        await tester.pump();
        await tester.tap(find.text('I'));
        await tester.pump();
        expect(messageText('OI'), findsOneWidget);

        await tester.tap(find.text('APAGAR'));
        await tester.pump();
        expect(messageText('O'), findsOneWidget);
      });

      testWidgets('FALAR usa a frase sem apagá-la', (tester) async {
        final synthesizer = _FakeSpeechSynthesizer();
        await tester.pumpWidget(
          MaterialApp(
            home: CommunicatorScreen(
              controlStyle: style,
              synthesizer: synthesizer,
            ),
          ),
        );
        await tester.pump();

        // Confirma Q, desce até FALAR e confirma novamente. É o mesmo caminho
        // que os comandos emitidos pelo rastreador de olhar percorrem.
        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
          await tester.pump();
        }
        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();

        expect(synthesizer.spoken, ['Q']);
        expect(messageText('Q'), findsOneWidget);
      });
    });
  }

  testWidgets('o app usa o arranjo de bordas por padrão', (tester) async {
    await tester.pumpWidget(const ElaCommunicatorApp());
    await tester.pump();

    expect(find.text('CONFIRMAR'), findsOneWidget);
  });

  test('o modelo recomenda a próxima palavra pelo contexto', () {
    final predictor = WordPredictor(phrases: WordPredictor.defaultPhrases);

    expect(predictor.suggest('eu quero'), contains('beber'));
    expect(predictor.suggest('eu quero b'), contains('beber'));
  });

  // O modelo padrão vem dos assets de forma assíncrona e não termina de
  // carregar num teste; um modelo pronto deixa as sugestões disponíveis.
  final defaultPredictor = WordPredictor(phrases: WordPredictor.defaultPhrases);

  Future<void> typeKeys(WidgetTester tester, List<String> keys) async {
    for (final key in keys) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
  }

  testWidgets('uma sugestão completa a palavra atual', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CommunicatorScreen(wordPredictor: defaultPredictor)),
    );
    await tester.pump();

    for (final key in ['E', 'U', 'ESPAÇO', 'Q', 'U', 'E', 'R', 'O']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('BEBER'));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(MessageBar),
        matching: find.textContaining('EU QUERO BEBER'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('as setas selecionam uma sugestão do auto-complete', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CommunicatorScreen(wordPredictor: defaultPredictor)),
    );
    await tester.pump();

    for (final key in ['E', 'U', 'ESPAÇO', 'Q', 'U', 'E', 'R', 'O']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }

    // Sobe do teclado para as sugestões e avança de BEBER para COMER.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(MessageBar),
        matching: find.textContaining('EU QUERO COMER'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sugestão que também é uma palavra frequente completa a palavra '
      'pela metade', (tester) async {
    // "de" é a palavra mais frequente: depois de "D " ela seria sugerida
    // como próxima palavra, mas em "EU QUERO D" ela completa o "D".
    final predictor = WordPredictor(
      phrases: ['eu quero dormir', 'preciso de ajuda', 'gosto de café'],
    );
    await tester.pumpWidget(
      MaterialApp(home: CommunicatorScreen(wordPredictor: predictor)),
    );
    await tester.pump();

    await typeKeys(tester, [
      'E', 'U', 'ESPAÇO', 'Q', 'U', 'E', 'R', 'O', 'ESPAÇO', 'D', //
    ]);
    expect(predictor.suggest('EU QUERO D '), contains('de'));
    await tester.tap(find.text('DE'));
    await tester.pump();

    expect(messageText('EU QUERO DE '), findsOneWidget);
  });

  testWidgets('a tecla FALAR mostra o estado do sintetizador', (tester) async {
    final synthesizer = _FakeSpeechSynthesizer();
    await tester.pumpWidget(
      MaterialApp(home: CommunicatorScreen(synthesizer: synthesizer)),
    );
    await tester.pump();

    await tester.tap(find.text('Q').last);
    await tester.pump();
    synthesizer.notifier.value = SpeechSynthesizerState.synthesizing;
    await tester.pump();
    expect(find.text('GERANDO'), findsOneWidget);

    synthesizer.notifier.value = SpeechSynthesizerState.playing;
    await tester.pump();
    expect(find.text('FALANDO'), findsOneWidget);
  });
}
