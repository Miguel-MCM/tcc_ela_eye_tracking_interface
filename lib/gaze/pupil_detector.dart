import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Estágio 2: centro da pupila dentro do recorte de olho.
///
/// O modelo é o YOLO26n treinado no MPIIGaze, exportado para TFLite em **FP32**.
///
/// Não troque por quantização dinâmica: o build de TFLite embutido no
/// tflite_flutter 0.12.1 não materializa os pesos INT8 híbridos e o invoke
/// falha com "Input tensor N lacks data" — verificado no aparelho. O INT8
/// completo funcionaria, mas devolve a saída crua `[1,5,336]`, que exigiria
/// implementar NMS aqui.
///
/// Entrada  `[1, 3, 128, 128]` float32, RGB em [0,1], NCHW.
/// Saída    `[1, 300, 6]` float32, já pós-NMS: `[x1, y1, x2, y2, conf, classe]`
///          em pixels do recorte.
class PupilDetector {
  PupilDetector._(this._interpreter, this.inputSize)
      : _input = _interpreter.getInputTensor(0),
        _output = _interpreter.getOutputTensor(0);

  final Interpreter _interpreter;
  final int inputSize;

  // Içados para fora do laço: reconstruir os wrappers a cada quadro custava
  // mais que a própria inferência. Só valem porque nada aqui redimensiona
  // tensores — se isso mudar, os ponteiros nativos deixam de valer.
  final Tensor _input;
  final Tensor _output;

  /// Buffer a preencher com o recorte (NCHW, RGB, [0,1]) antes de [detect].
  ///
  /// Não dá para escrever direto no tensor nativo: `Tensor.data` devolve uma
  /// view imutável, e views derivadas dela também são imutáveis. Então este é
  /// um buffer próprio, copiado para o tensor no [detect] — uma cópia por olho,
  /// em vez das listas aninhadas que custavam 53 ms.
  late final Float32List inputBuffer = Float32List(_input.numBytes() ~/ 4);

  static const String assetPath = 'assets/models/pupil_128.tflite';

  /// Limiar baixo de propósito: por construção todo recorte contém exatamente
  /// uma pupila, então a tarefa é escolher o melhor candidato, não decidir se
  /// existe pupila. O modelo também é sistematicamente subconfiante (confianças
  /// em torno de 0,20).
  static const double defaultConfidence = 0.01;

  static Future<PupilDetector> load({int threads = 2}) async {
    // Carregado à mão em vez de Interpreter.fromAsset só para poder logar o
    // tamanho: `fromAsset` ignora offsetInBytes/lengthInBytes do ByteData, o
    // que seria um bug se o asset não começasse no offset 0 — aqui começa.
    final raw = await rootBundle.load(assetPath);
    final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    debugPrint('[gaze] modelo: ${bytes.length} bytes '
        '(offset ${raw.offsetInBytes}, buffer ${raw.buffer.lengthInBytes})');

    final options = InterpreterOptions()..threads = threads;
    final interpreter = Interpreter.fromBuffer(bytes, options: options);
    final shape = interpreter.getInputTensor(0).shape; // [1, 3, S, S]
    final detector = PupilDetector._(interpreter, shape.last);

    // Uma inferência de teste no carregamento. Sem ela, um modelo quebrado só
    // apareceria como quadros descartados em silêncio, quando houvesse rosto.
    detector.inputBuffer.fillRange(0, detector.inputBuffer.length, 0);
    detector.detect(); // a primeira inclui alocação de tensores
    final started = DateTime.now();
    for (var i = 0; i < 5; i++) {
      detector.detect();
    }
    final perRun = DateTime.now().difference(started).inMilliseconds / 5;
    debugPrint('[gaze] modelo ok: entrada $shape, $perRun ms por inferência '
        '(dois olhos por quadro)');
    return detector;
  }

  /// Devolve o centro da pupila em coordenadas do recorte, ou null.
  /// Roda sobre o que estiver em [inputBuffer].
  ({math.Point<double> center, double confidence})? detect({
    double confidence = defaultConfidence,
  }) {
    // Lê a saída direto do buffer nativo. Passar por listas aninhadas
    // (`run` + `reshape`) custava 53 dos 68 ms por inferência neste tablet,
    // contra 15 ms de inferência de verdade — o gargalo era marshalling.
    _input.data = inputBuffer.buffer
        .asUint8List(inputBuffer.offsetInBytes, inputBuffer.lengthInBytes);
    _interpreter.invoke();

    final raw = _output.data;
    final rows = raw.buffer.asFloat32List(raw.offsetInBytes, raw.lengthInBytes ~/ 4);

    var bestScore = confidence;
    var bestRow = -1;
    for (var i = 0; i + 5 < rows.length; i += 6) {
      if (rows[i + 4] > bestScore) {
        bestScore = rows[i + 4];
        bestRow = i;
      }
    }
    if (bestRow < 0) return null;

    return (
      center: math.Point(
        (rows[bestRow] + rows[bestRow + 2]) / 2,
        (rows[bestRow + 1] + rows[bestRow + 3]) / 2,
      ),
      confidence: bestScore,
    );
  }

  void close() => _interpreter.close();
}
