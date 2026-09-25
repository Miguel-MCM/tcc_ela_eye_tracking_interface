import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tcc_ela_eye_tracking_interface/main.dart';
import 'package:tcc_ela_eye_tracking_interface/models/control_style.dart';
import 'package:tcc_ela_eye_tracking_interface/models/word_predictor.dart';
import 'package:tcc_ela_eye_tracking_interface/screens/communicator_screen.dart';
import 'package:tcc_ela_eye_tracking_interface/widgets/message_bar.dart';

/// Texto atualmente na faixa de mensagem (ignora as teclas de mesmo rótulo).
Finder messageText(String text) =>
    find.descendant(of: find.byType(MessageBar), matching: find.text(text));

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
        // final, que só tem três teclas.
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
    });
  }

  testWidgets('o app usa o arranjo de bordas por padrão', (tester) async {
    await tester.pumpWidget(const ElaCommunicatorApp());
    await tester.pump();

    expect(find.text('CONFIRMAR'), findsOneWidget);
  });

  test('o modelo recomenda a próxima palavra pelo contexto', () {
    final predictor = WordPredictor.defaultModel();

    expect(predictor.suggest('eu quero'), contains('beber'));
    expect(predictor.suggest('eu quero b'), contains('beber'));
  });

  testWidgets('uma sugestão completa a palavra atual', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunicatorScreen()));
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
}
