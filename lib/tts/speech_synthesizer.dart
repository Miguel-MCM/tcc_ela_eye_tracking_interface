import 'package:flutter/foundation.dart';

/// Fase atual do sintetizador.
enum SpeechSynthesizerState {
  idle,
  preparing,
  synthesizing,
  playing,
  error,
  disposed;

  bool get isBusy =>
      this == preparing || this == synthesizing || this == playing;
}

/// Contrato pequeno para a tela não depender do runtime de síntese.
///
/// Também permite usar um fake nos testes de widget, onde plugins nativos e o
/// modelo ONNX não estão disponíveis.
abstract interface class SpeechSynthesizer {
  ValueListenable<SpeechSynthesizerState> get state;

  Future<void> initialize();

  /// Sintetiza e reproduz [text]. A Future termina quando o áudio acaba.
  Future<void> speak(String text);

  /// Impede que uma síntese em andamento comece a tocar e para a reprodução.
  Future<void> stop();

  Future<void> dispose();
}

/// Falha recuperável de preparação, inferência ou reprodução.
class SpeechSynthesisException implements Exception {
  const SpeechSynthesisException(this.message, [this.remoteStackTrace]);

  final String message;
  final String? remoteStackTrace;

  @override
  String toString() => 'SpeechSynthesisException: $message';
}
