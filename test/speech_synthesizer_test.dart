import 'package:flutter_test/flutter_test.dart';
import 'package:tcc_ela_eye_tracking_interface/tts/kokoro_synthesizer.dart';
import 'package:tcc_ela_eye_tracking_interface/tts/speech_synthesizer.dart';

void main() {
  test('estados de trabalho são identificados como ocupados', () {
    expect(SpeechSynthesizerState.preparing.isBusy, isTrue);
    expect(SpeechSynthesizerState.synthesizing.isBusy, isTrue);
    expect(SpeechSynthesizerState.playing.isBusy, isTrue);
    expect(SpeechSynthesizerState.idle.isBusy, isFalse);
    expect(SpeechSynthesizerState.error.isBusy, isFalse);
  });

  test('frase vazia é rejeitada sem inicializar o runtime', () async {
    final synthesizer = KokoroSynthesizer();

    expect(() => synthesizer.speak('   '), throwsArgumentError);
    expect(synthesizer.state.value, SpeechSynthesizerState.idle);

    await synthesizer.dispose();
    expect(synthesizer.state.value, SpeechSynthesizerState.disposed);
  });
}
