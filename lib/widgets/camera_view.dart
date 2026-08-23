import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Prévia da câmera frontal.
///
/// Hoje serve só para o usuário se posicionar no enquadramento. O módulo de
/// eye tracking vai consumir os frames desta mesma câmera — por isso o
/// controlador fica exposto via [onControllerReady].
class CameraView extends StatefulWidget {
  const CameraView({super.key, this.onControllerReady});

  /// Chamado quando a câmera termina de inicializar (e com `null` quando ela é
  /// liberada, por exemplo ao mandar o app para segundo plano).
  final ValueChanged<CameraController?>? onControllerReady;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A câmera precisa ser liberada em segundo plano, senão o Android derruba
    // a sessão e a prévia volta congelada.
    if (state == AppLifecycleState.inactive) {
      _release();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  void _release() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _controller = null);
    widget.onControllerReady?.call(null);
    controller.dispose();
  }

  Future<void> _start() async {
    if (_initializing || _controller != null) return;
    _initializing = true;
    setState(() => _error = null);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('sem_camera', 'Nenhuma câmera disponível.');
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        // Resolução baixa basta para o enquadramento e deixa sobra de CPU
        // para a detecção facial que virá depois.
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() => _controller = controller);
      widget.onControllerReady?.call(controller);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _initializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, color: theme.colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _start,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // BoxFit.cover recorta as bordas em vez de distorcer o rosto — importante
    // porque a proporção da prévia raramente bate com a do espaço na tela.
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? 1,
        height: controller.value.previewSize?.width ?? 1,
        child: CameraPreview(controller),
      ),
    );
  }
}
