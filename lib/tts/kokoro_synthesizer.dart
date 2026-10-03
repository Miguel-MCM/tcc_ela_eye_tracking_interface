import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_synthesizer.dart';

typedef DirectoryProvider = Future<Directory> Function();

/// Sintetizador Kokoro offline com inferência numa isolate persistente.
class KokoroSynthesizer implements SpeechSynthesizer {
  KokoroSynthesizer({
    AssetBundle? assetBundle,
    DirectoryProvider? supportDirectory,
    DirectoryProvider? temporaryDirectory,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static const _assetRoot = 'assets/models/kokoro_pt';

  final AssetBundle _assetBundle;
  final DirectoryProvider _supportDirectory;
  final DirectoryProvider _temporaryDirectory;
  final ValueNotifier<SpeechSynthesizerState> _state = ValueNotifier(
    SpeechSynthesizerState.idle,
  );
  final Map<int, Completer<Object?>> _requests = {};

  Future<void>? _initialization;
  Future<void>? _activeSpeak;
  ReceivePort? _workerReceivePort;
  StreamSubscription<Object?>? _workerSubscription;
  Isolate? _worker;
  SendPort? _workerPort;
  Completer<void>? _workerReady;
  AudioPlayer? _player;
  Completer<void>? _playback;
  late Directory _audioDirectory;
  int _nextRequestId = 1;
  bool _stopRequested = false;
  bool _disposing = false;
  bool _disposed = false;

  @override
  ValueListenable<SpeechSynthesizerState> get state => _state;

  @override
  Future<void> initialize() {
    _checkNotDisposed();
    if (_workerPort != null) return Future.value();
    final current = _initialization;
    if (current != null) return current;

    final operation = _initialize();
    _initialization = operation;
    return operation;
  }

  Future<void> _initialize() async {
    _setState(SpeechSynthesizerState.preparing);
    try {
      final modelDirectory = await _materializeModel();
      final temporaryRoot = await _temporaryDirectory();
      _audioDirectory = Directory(
        _join(temporaryRoot.path, 'tts_audio'),
      );
      await _audioDirectory.create(recursive: true);
      await _removeStaleAudio();
      await _spawnWorker(modelDirectory);
      _setState(SpeechSynthesizerState.idle);
    } catch (_) {
      _setState(SpeechSynthesizerState.error);
      _initialization = null;
      await _tearDownWorker();
      rethrow;
    }
  }

  @override
  Future<void> speak(String text) {
    _checkNotDisposed();
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(text, 'text', 'a frase não pode estar vazia');
    }
    if (_activeSpeak != null) {
      throw StateError('já existe uma síntese em andamento');
    }

    _stopRequested = false;
    late final Future<void> operation;
    operation = _speak(normalized).whenComplete(() {
      if (identical(_activeSpeak, operation)) _activeSpeak = null;
    });
    _activeSpeak = operation;
    return operation;
  }

  Future<void> _speak(String text) async {
    try {
      await initialize();
      if (_stopRequested) return;

      _setState(SpeechSynthesizerState.synthesizing);
      final synthesisWatch = Stopwatch()..start();
      final outputPath = _join(
        _audioDirectory.path,
        'speech_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      final result = await _request('synthesize', {
        'text': text,
        'outputPath': outputPath,
      });
      final audioPath = result as String;
      synthesisWatch.stop();
      debugPrint(
        '[tts] síntese concluída em '
        '${synthesisWatch.elapsedMilliseconds} ms',
      );
      if (_stopRequested) {
        await _deleteIfPresent(audioPath);
        return;
      }

      _setState(SpeechSynthesizerState.playing);
      try {
        debugPrint('[tts] reproduzindo $audioPath');
        await _play(audioPath);
        debugPrint('[tts] reprodução concluída');
      } finally {
        await _deleteIfPresent(audioPath);
      }
    } catch (error, stackTrace) {
      _setState(SpeechSynthesizerState.error);
      if (error is SpeechSynthesisException) rethrow;
      Error.throwWithStackTrace(SpeechSynthesisException('$error'), stackTrace);
    } finally {
      if (!_disposed && _state.value != SpeechSynthesizerState.error) {
        _setState(SpeechSynthesizerState.idle);
      }
    }
  }

  Future<void> _play(String path) async {
    final player = _player ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    if (_stopRequested) return;

    final completed = Completer<void>();
    _playback = completed;
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completed.isCompleted) completed.complete();
    });
    try {
      await player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
      await completed.future;
    } finally {
      await subscription.cancel();
      if (identical(_playback, completed)) _playback = null;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _stopRequested = true;
    await _player?.stop();
    final playback = _playback;
    if (playback != null && !playback.isCompleted) playback.complete();
  }

  @override
  Future<void> dispose() async {
    if (_disposed || _disposing) return;
    _disposing = true;
    await stop();

    try {
      await _activeSpeak;
    } catch (_) {
      // O chamador da síntese recebe a falha original; dispose só limpa.
    }
    try {
      await _initialization;
    } catch (_) {
      // Uma inicialização que falhou já liberou a isolate no próprio catch.
    }

    if (_workerPort != null) {
      try {
        await _request('dispose').timeout(const Duration(seconds: 5));
      } catch (_) {
        _worker?.kill(priority: Isolate.immediate);
      }
    }
    await _tearDownWorker();
    await _player?.dispose();
    _player = null;
    _disposed = true;
    _disposing = false;
    _setState(SpeechSynthesizerState.disposed);
  }

  Future<Directory> _materializeModel() async {
    final supportRoot = await _supportDirectory();
    final destination = Directory(_join(supportRoot.path, 'kokoro_pt'));
    await destination.create(recursive: true);

    final assetManifest = await _assetBundle.loadString(
      '$_assetRoot/manifest.json',
    );
    final localManifest = File(_join(destination.path, 'manifest.json'));
    if (await _cacheIsCurrent(destination, localManifest, assetManifest)) {
      return destination;
    }

    for (final filename in _manifestFiles(assetManifest).keys) {
      await _copyAsset(
        '$_assetRoot/$filename',
        File(_join(destination.path, filename)),
      );
    }
    await _writeAtomically(localManifest, utf8.encode(assetManifest));
    return destination;
  }

  Future<bool> _cacheIsCurrent(
    Directory destination,
    File localManifest,
    String assetManifest,
  ) async {
    if (!await localManifest.exists()) return false;
    if (await localManifest.readAsString() != assetManifest) return false;

    for (final MapEntry(key: filename, value: metadata)
        in _manifestFiles(assetManifest).entries) {
      final file = File(_join(destination.path, filename));
      if (!await file.exists()) return false;
      if (await file.length() != metadata['size'] as int) return false;
    }
    return true;
  }

  static Map<String, Map<String, Object?>> _manifestFiles(String manifest) {
    final files =
        (jsonDecode(manifest) as Map<String, Object?>)['files']!
            as Map<String, Object?>;
    return files.cast<String, Map<String, Object?>>();
  }

  Future<void> _copyAsset(String assetPath, File destination) async {
    final data = await _assetBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await _writeAtomically(destination, bytes);
  }

  static Future<void> _writeAtomically(
    File destination,
    List<int> bytes,
  ) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  static Future<void> _deleteIfPresent(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // O WAV é temporário; uma limpeza concorrente não invalida a fala.
    }
  }

  Future<void> _removeStaleAudio() async {
    await for (final entity in _audioDirectory.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        await _deleteIfPresent(entity.path);
      }
    }
  }

  Future<void> _spawnWorker(Directory modelDirectory) async {
    final receivePort = ReceivePort();
    _workerReceivePort = receivePort;
    _workerReady = Completer<void>();
    _workerSubscription = receivePort.cast<Object?>().listen(
      _handleWorkerMessage,
    );
    _worker = await Isolate.spawn<Map<String, Object?>>(
      _kokoroWorker,
      {'replyTo': receivePort.sendPort, 'modelDirectory': modelDirectory.path},
      onError: receivePort.sendPort,
      onExit: receivePort.sendPort,
      errorsAreFatal: true,
      debugName: 'kokoro-tts',
    );
    await _workerReady!.future;
  }

  void _handleWorkerMessage(Object? rawMessage) {
    if (rawMessage == null) {
      if (!_disposing) _failWorker('a isolate de síntese foi encerrada');
      return;
    }
    if (rawMessage is List) {
      _failWorker(rawMessage.join('\n'));
      return;
    }

    final message = rawMessage as Map<Object?, Object?>;
    switch (message['type']) {
      case 'ready':
        _workerPort = message['port']! as SendPort;
        final ready = _workerReady;
        if (ready != null && !ready.isCompleted) ready.complete();
      case 'response':
        final id = message['id']! as int;
        final completer = _requests.remove(id);
        if (completer == null) return;
        if (message['ok'] == true) {
          completer.complete(message['result']);
        } else {
          completer.completeError(
            SpeechSynthesisException(
              message['error']! as String,
              message['stackTrace'] as String?,
            ),
          );
        }
      case 'fatal':
        _failWorker(
          message['error']! as String,
          message['stackTrace'] as String?,
        );
    }
  }

  void _failWorker(String message, [String? stackTrace]) {
    final error = SpeechSynthesisException(message, stackTrace);
    _workerPort = null;
    _initialization = null;
    final ready = _workerReady;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final completer in _requests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _requests.clear();
  }

  Future<Object?> _request(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) {
    final port = _workerPort;
    if (port == null) {
      throw StateError('o runtime Kokoro ainda não foi inicializado');
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _requests[id] = completer;
    port.send({'command': command, 'id': id, ...arguments});
    return completer.future;
  }

  Future<void> _tearDownWorker() async {
    _workerPort = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    await _workerSubscription?.cancel();
    _workerSubscription = null;
    _workerReceivePort?.close();
    _workerReceivePort = null;
    _workerReady = null;
  }

  void _setState(SpeechSynthesizerState value) {
    if (_state.value != value) _state.value = value;
  }

  void _checkNotDisposed() {
    if (_disposed || _disposing) {
      throw StateError('o sintetizador já foi descartado');
    }
  }

  /// [child] usa `/` como nos caminhos de asset.
  static String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}'
      '${child.replaceAll('/', Platform.pathSeparator)}';
}

/// Voz `pf_dora` (português brasileiro, feminina) na tabela do Kokoro v1.0.
const _voiceId = 42;

/// Mantém o modelo nativo vivo fora da isolate da interface.
Future<void> _kokoroWorker(Map<String, Object?> bootstrap) async {
  final replyTo = bootstrap['replyTo']! as SendPort;
  final modelDirectory = bootstrap['modelDirectory']! as String;
  String path(String name) => KokoroSynthesizer._join(modelDirectory, name);
  sherpa.OfflineTts? tts;

  try {
    sherpa.initBindings();
    tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: path('model.onnx'),
            voices: path('voices.bin'),
            tokens: path('tokens.txt'),
            dataDir: path('espeak-ng-data'),
            lang: 'pt-br',
          ),
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
      ),
    );

    final commands = ReceivePort();
    replyTo.send({'type': 'ready', 'port': commands.sendPort});
    await for (final rawMessage in commands) {
      final message = rawMessage as Map<Object?, Object?>;
      final id = message['id']! as int;
      try {
        switch (message['command']) {
          case 'synthesize':
            final audio = tts.generate(
              text: message['text']! as String,
              sid: _voiceId,
            );
            if (audio.samples.isEmpty || audio.sampleRate == 0) {
              throw StateError('o Kokoro não gerou áudio');
            }

            debugPrint(
              '[tts] áudio gerado: ${audio.samples.length} amostras, '
              '${audio.sampleRate} Hz',
            );
            final outputPath = message['outputPath']! as String;
            final written = sherpa.writeWave(
              filename: outputPath,
              samples: audio.samples,
              sampleRate: audio.sampleRate,
            );
            if (!written) {
              throw FileSystemException(
                'não foi possível salvar o áudio sintetizado',
                outputPath,
              );
            }
            replyTo.send({
              'type': 'response',
              'id': id,
              'ok': true,
              'result': outputPath,
            });
          case 'dispose':
            replyTo.send({'type': 'response', 'id': id, 'ok': true});
            commands.close();
        }
      } catch (error, stackTrace) {
        replyTo.send({
          'type': 'response',
          'id': id,
          'ok': false,
          'error': '$error',
          'stackTrace': '$stackTrace',
        });
      }
    }
  } catch (error, stackTrace) {
    replyTo.send({
      'type': 'fatal',
      'error': '$error',
      'stackTrace': '$stackTrace',
    });
  } finally {
    tts?.free();
  }
}
