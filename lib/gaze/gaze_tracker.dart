import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import '../models/gaze_command.dart';
import 'camera_frame.dart';
import 'eye_crop.dart';
import 'gaze_kalman.dart';
import 'gaze_mapper.dart';
import 'pupil_detector.dart';

/// Índices dos cantos dos olhos na malha de 468 pontos.
///
/// O ML Kit usa a mesma topologia do MediaPipe Face Mesh, então são os mesmos
/// índices do PoC em Python. A ordem segue a convenção do MPIIGaze: o vetor
/// A -> B aponta no sentido +x da imagem nos dois olhos, o que mantém o
/// alinhamento de roll consistente entre os lados.
const Map<String, (int, int)> kEyeCorners = {
  'right': (33, 133),
  'left': (362, 263),
};

/// Quanto a tela está girada em relação à orientação natural do aparelho.
const Map<DeviceOrientation, int> _kDeviceDegrees = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Rotação que leva o buffer da câmera à imagem em pé.
///
/// Não basta o `sensorOrientation`: num tablet em paisagem a tela está girada
/// 90°, e usar só o sensor deixa o rosto deitado — o Face Mesh então falha na
/// esmagadora maioria dos quadros. A fórmula é a canônica do ML Kit, e o sinal
/// se inverte entre câmera frontal e traseira.
int rotationDegreesFor(CameraDescription camera, DeviceOrientation device) {
  final deviceDegrees = _kDeviceDegrees[device] ?? 0;
  return camera.lensDirection == CameraLensDirection.front
      ? (camera.sensorOrientation + deviceDegrees) % 360
      : (camera.sensorOrientation - deviceDegrees + 360) % 360;
}

/// Estado publicado a cada quadro processado.
class GazeSample {
  const GazeSample({
    required this.point,
    required this.command,
    required this.eyesFound,
    required this.faceFound,
  });

  /// Olhar em fração de tela [0,1], já suavizado. Null enquanto não calibrado
  /// ou sem rosto.
  final math.Point<double>? point;
  final GazeCommand? command;
  final int eyesFound;
  final bool faceFound;
}

/// Estágio 1 + estágio 2 + mapeamento, consumindo o stream da câmera.
///
/// Emite [GazeSample] continuamente e [commands] apenas quando um dwell
/// completa — é [commands] que a tela liga em `_handleCommand`.
class GazeTracker {
  GazeTracker({
    required this.detector,
    required this.cropParams,
    this.dwell = const Duration(milliseconds: 1500),
    this.smoothing = const Duration(milliseconds: 500),
    this.bands = const GazeBands(),
    this.meshEveryNFrames = 3,
    this.maxCornerAge = const Duration(milliseconds: 400),
    this.cornerHistory = 5,
  });

  final PupilDetector detector;
  final CropParams cropParams;
  final Duration dwell;
  final Duration smoothing;
  final GazeBands bands;

  /// O Face Mesh custa ~100 ms com rosto, contra ~38 ms dos dois olhos juntos
  /// (medido num Galaxy Tab S9 FE a 480p). Como os cantos do olho se movem
  /// devagar e a pupila se move rápido, vale reaproveitá-los entre quadros —
  /// é o que triplica a taxa. [maxCornerAge] limita o quanto podem envelhecer
  /// quando a taxa cai.
  final int meshEveryNFrames;
  final Duration maxCornerAge;

  /// Quantas leituras do mesh entram na mediana dos cantos.
  ///
  /// `v` divide pela distância entre os cantos, então o tremor deles entra
  /// direto no sinal — e medindo na calibração ele domina o ruído (0,09 contra
  /// 0,03 do detector de pupila). Os cantos se movem devagar, então tirar a
  /// mediana de várias leituras corta esse tremor quase de graça.
  final int cornerHistory;

  final _faceMesh = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
  final _samples = StreamController<GazeSample>.broadcast();
  final _commands = StreamController<GazeCommand>.broadcast();

  Stream<GazeSample> get samples => _samples.stream;
  Stream<GazeCommand> get commands => _commands.stream;

  GazeMap? _map;
  GazeMap? get map => _map;
  set map(GazeMap? value) {
    _map = value;
    _kalman.reset();
  }

  bool _busy = false;
  GazeCommand? _dwellCommand;
  DateTime _dwellStart = DateTime.now();

  // Diagnóstico: sem isto, "não está funcionando" não diz em qual estágio.
  final _cornerHistory = <Map<String, (math.Point<double>, math.Point<double>)>>[];
  Map<String, (math.Point<double>, math.Point<double>)>? _corners;
  DateTime _cornersAt = DateTime.now();
  int _rotationOfCorners = -1;
  int _sinceMesh = 0;

  DateTime _statsAt = DateTime.now();
  int _frames = 0, _faces = 0, _eyes = 0;
  int _meshUs = 0, _pupilUs = 0;

  /// Última feature bruta, consumida pela tela de calibração.
  math.Point<double>? lastFeature;

  final _kalman = GazeKalman();

  static Future<CropParams> loadCropParams() async {
    final raw = await rootBundle.loadString('assets/models/crop_params.json');
    return CropParams.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Liga o tracker ao controlador da câmera.
  ///
  /// Exige `ImageFormatGroup.nv21`: é o formato que o ML Kit aceita no Android
  /// e o mesmo que [Nv21Frame] amostra, evitando qualquer conversão de quadro.
  CameraController? _controller;

  Future<void> attach(CameraController controller) async {
    _controller = controller;
    debugPrint('[gaze] câmera: sensor ${controller.description.sensorOrientation}° '
        '${controller.description.lensDirection.name}, '
        'aparelho ${controller.value.deviceOrientation.name}');
    await controller.startImageStream((image) => _onFrame(image, controller.description));
  }

  Future<void> _onFrame(CameraImage image, CameraDescription camera) async {
    // Descarta quadros enquanto o anterior roda: a fila da câmera cresceria e o
    // olhar exibido ficaria cada vez mais atrasado em relação ao real.
    //
    // ponytail: a inferência dos dois olhos roda síncrona na isolate da UI, o
    // que pode travar quadros de animação. Meça antes de mexer; se travar, mova
    // PupilDetector para uma isolate com `Interpreter.fromAddress`.
    if (_busy) return;
    _busy = true;
    try {
      await _process(image, camera);
    } catch (e, s) {
      debugPrint('[gaze] quadro descartado: $e\n$s');
    } finally {
      _busy = false;
    }
  }

  Future<void> _process(CameraImage image, CameraDescription camera) async {
    // O mesmo valor alimenta o ML Kit e a amostragem: se divergirem, os
    // landmarks e o recorte passam a viver em espaços diferentes.
    final degrees = rotationDegreesFor(
      camera,
      _controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp,
    );
    final rotation =
        InputImageRotationValue.fromRawValue(degrees) ?? InputImageRotation.rotation0deg;
    final bytes = image.planes.first.bytes;
    final frame = Nv21Frame(bytes, image.width, image.height, degrees);

    // Reaproveita os cantos por alguns quadros; sem isto o mesh domina o custo.
    final stale = _corners == null ||
        _rotationOfCorners != degrees ||
        _sinceMesh >= meshEveryNFrames ||
        DateTime.now().difference(_cornersAt) > maxCornerAge;

    if (stale) {
      final meshStart = DateTime.now();
      final meshes = await _faceMesh.processImage(InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ));
      _meshUs += DateTime.now().difference(meshStart).inMicroseconds;
      _sinceMesh = 0;

      if (meshes.isEmpty) {
        _corners = null;
        _cornerHistory.clear();
        _emit(const GazeSample(point: null, command: null, eyesFound: 0, faceFound: false));
        return;
      }
      final fresh = _cornersFrom(meshes.first.points, frame);
      if (fresh != null) {
        _cornerHistory.add(fresh);
        while (_cornerHistory.length > cornerHistory) {
          _cornerHistory.removeAt(0);
        }
      }
      _corners = _smoothedCorners();
      _cornersAt = DateTime.now();
      _rotationOfCorners = degrees;
    } else {
      _sinceMesh++;
    }

    final corners = _corners;
    if (corners == null) {
      _emit(const GazeSample(point: null, command: null, eyesFound: 0, faceFound: false));
      return;
    }

    final features = <math.Point<double>>[];
    for (final entry in corners.entries) {
      final (a, b) = entry.value;
      final transform = cropTransform(a, b, cropParams);
      final pupilStart = DateTime.now();
      frame.sampleCrop(transform, cropParams.cropSize, detector.inputBuffer);
      final hit = detector.detect();
      _pupilUs += DateTime.now().difference(pupilStart).inMicroseconds;
      if (hit == null) continue;

      features.add(eyeFeature(a, b, transform.toFrame(hit.center)));
    }

    if (features.isEmpty) {
      _emit(GazeSample(point: null, command: null, eyesFound: 0, faceFound: true));
      return;
    }

    // Média dos dois olhos: reduz o ruído de detecção por raiz de 2.
    lastFeature = math.Point(
      features.map((f) => f.x).reduce((a, b) => a + b) / features.length,
      features.map((f) => f.y).reduce((a, b) => a + b) / features.length,
    );

    final gazeMap = _map;
    if (gazeMap == null) {
      _emit(GazeSample(point: null, command: null, eyesFound: features.length, faceFound: true));
      return;
    }

    final now = DateTime.now();
    final measurement = gazeMap.predict(lastFeature!) ;
    final point = _kalman.update(measurement, now);
    final command = commandFor(point, bands);
    _updateDwell(command);
    _emit(GazeSample(
      point: point,
      command: command,
      eyesFound: features.length,
      faceFound: true,
    ));
  }

  /// Mediana das últimas leituras de cada canto, para cortar o tremor do mesh.
  Map<String, (math.Point<double>, math.Point<double>)>? _smoothedCorners() {
    if (_cornerHistory.isEmpty) return null;
    final out = <String, (math.Point<double>, math.Point<double>)>{};
    for (final side in kEyeCorners.keys) {
      final entries = _cornerHistory.map((h) => h[side]).nonNulls.toList();
      if (entries.isEmpty) continue;
      out[side] = (
        _medianPoint(entries.map((e) => e.$1).toList()),
        _medianPoint(entries.map((e) => e.$2).toList()),
      );
    }
    return out.isEmpty ? null : out;
  }

  /// Desvio típico do canto externo direito no histórico — só diagnóstico.
  double _cornerJitter() {
    final pts = _cornerHistory.map((h) => h["right"]?.$1).nonNulls.toList();
    if (pts.length < 2) return 0;
    final mx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    final my = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;
    final v = pts
            .map((p) => math.pow(p.x - mx, 2) + math.pow(p.y - my, 2))
            .reduce((a, b) => a + b) /
        pts.length;
    return math.sqrt(v);
  }

  static math.Point<double> _medianPoint(List<math.Point<double>> points) {
    final xs = points.map((p) => p.x).toList()..sort();
    final ys = points.map((p) => p.y).toList()..sort();
    return math.Point(xs[xs.length ~/ 2], ys[ys.length ~/ 2]);
  }

  /// Landmarks do ML Kit (espaço em pé) para cantos no espaço bruto do buffer.
  Map<String, (math.Point<double>, math.Point<double>)>? _cornersFrom(
    List<FaceMeshPoint> points,
    Nv21Frame frame,
  ) {
    final out = <String, (math.Point<double>, math.Point<double>)>{};
    for (final entry in kEyeCorners.entries) {
      final (ia, ib) = entry.value;
      if (ia >= points.length || ib >= points.length) continue;
      out[entry.key] = (
        frame.toRaw(math.Point(points[ia].x.toDouble(), points[ia].y.toDouble())),
        frame.toRaw(math.Point(points[ib].x.toDouble(), points[ib].y.toDouble())),
      );
    }
    return out.isEmpty ? null : out;
  }

  void _updateDwell(GazeCommand command) {
    final now = DateTime.now();
    if (command != _dwellCommand) {
      _dwellCommand = command;
      _dwellStart = now;
      return;
    }
    if (now.difference(_dwellStart) >= dwell) {
      _commands.add(command);
      _dwellStart = now; // rearma para não repetir em rajada
    }
  }

  /// Progresso do dwell atual, de 0 a 1 — para a interface mostrar o alvo enchendo.
  double get dwellProgress {
    if (_dwellCommand == null) return 0;
    final elapsed = DateTime.now().difference(_dwellStart).inMilliseconds;
    return (elapsed / dwell.inMilliseconds).clamp(0.0, 1.0);
  }

  GazeCommand? get dwellCommand => _dwellCommand;

  void _emit(GazeSample sample) {
    if (!_samples.isClosed) _samples.add(sample);

    _frames++;
    if (sample.faceFound) _faces++;
    _eyes += sample.eyesFound;
    final elapsed = DateTime.now().difference(_statsAt);
    if (elapsed.inMilliseconds >= 2000) {
      final fps = _frames * 1000 / elapsed.inMilliseconds;
      debugPrint('[gaze] ${fps.toStringAsFixed(1)} fps | rosto em $_frames '
          'quadros: $_faces | olhos/quadro: '
          '${(_eyes / _frames).toStringAsFixed(2)} | calibrado: ${_map != null}'
          ' | cantos±${_cornerJitter().toStringAsFixed(2)}px'
          ' | mesh ${(_meshUs / 1000 / _frames).toStringAsFixed(0)}ms'
          ' pupila ${(_pupilUs / 1000 / _frames).toStringAsFixed(0)}ms');
      _statsAt = DateTime.now();
      _frames = _faces = _eyes = 0;
      _meshUs = _pupilUs = 0;
    }
  }

  Future<void> dispose() async {
    await _faceMesh.close();
    await _samples.close();
    await _commands.close();
    detector.close();
  }
}
