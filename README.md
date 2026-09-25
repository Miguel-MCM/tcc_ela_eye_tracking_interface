# tcc_ela_eye_tracking_interface

Interface de comunicação por eye tracking para pacientes com ELA

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Rastreador de olhar

O app roda o rastreador na própria câmera frontal, sem servidor. Três estágios:

```
câmera (NV21) → ML Kit Face Mesh → cantos dos olhos
              → crop_eye() → recorte 128×128
              → pupil_128.tflite → centro da pupila
              → v = (pupila − centro dos cantos) / largura do olho
              → regressão calibrada → ponto na tela → GazeCommand
```

O rastreador emite exatamente os mesmos `GazeCommand` das setas, então entra pelo
`_handleCommand` sem que a interface mude.

| Arquivo | Papel |
|---|---|
| `lib/gaze/eye_crop.dart` | geometria do recorte — **espelha o treino**, travada por teste |
| `lib/gaze/camera_frame.dart` | amostra o recorte direto do NV21, sem converter o quadro |
| `lib/gaze/pupil_detector.dart` | inferência TFLite |
| `lib/gaze/gaze_mapper.dart` | vetor `v`, ajuste polinomial, zonas → comandos |
| `lib/gaze/gaze_tracker.dart` | junta tudo no stream da câmera |
| `lib/screens/calibration_screen.dart` | calibração em 9 alvos |

**Calibrar não é opcional.** O viés por pessoa responde por ~12% da energia do erro e
não some por média temporal: sem calibração o erro estaciona em torno de 3,4°, contra
~1,4° com ela. O ícone ao lado da câmera abre a calibração e mostra o estado.

### O que a calibração no aparelho ensinou

Medindo `v` alvo a alvo num Galaxy Tab S9 FE, três coisas ficaram claras — e nenhuma
delas era o que se suspeitava antes de medir:

**O sinal existe nos dois eixos.** Numa boa calibração a amplitude de `v` foi
`x 0,159` e `y 0,124`, contra ruído de ~0,03 — a vertical bate a ordem prevista pela
geometria (~0,11). Uma rodada anterior deu `y 0,028` e parecia provar que a vertical não
funcionava; era o usuário não fixando os alvos.

**O modelo não é o gargalo.** Ajustando os mesmos 9 pares reais: linear 18,0%, bilinear
16,8%, quadrático 15,4%. Mas **descartando o pior alvo, 12,1%**. O que estraga o
mapeamento são alvos individuais ruins, não a forma da função.

**Os alvos das quinas são os ruins.** Com margem de 12%, 3 dos 9 alvos saíram com erro
de 23% a 38% — todos nas quinas, onde a pessoa vira a cabeça em vez de mover os olhos.
Daí a margem de 20% e o `fitGazeMapRobust`.

**Os cantos do ML Kit dão picos.** O diagnóstico `cantos±Npx` mostra 0,1–1,8 px na maior
parte do tempo, mas **picos de 13 px**. Com olho de ~100 px isso é 0,13 em unidades de
`v` — sozinho basta para arruinar um alvo. Daí a mediana temporal dos cantos.

`test/gaze_mapper_test.dart` guarda os 9 pares reais medidos, então uma regressão nesse
caminho aparece no `flutter test` e não só no aparelho.

**Modelo.** `assets/models/pupil_128.tflite` (9,7 MB) é o YOLO26n treinado no MPIIGaze,
exportado em **FP32**. Entrada `[1,3,128,128]` float32 RGB em [0,1] (NCHW); saída
`[1,300,6]` já pós-NMS. Confere com o PyTorch em 0,07 px.

> **Não troque por quantização dinâmica.** O build de TFLite embutido no
> `tflite_flutter 0.12.1` não materializa os pesos INT8 híbridos: o `invoke` falha com
> `Input tensor 244 lacks data` e **todo quadro é descartado em silêncio**. Verificado no
> Galaxy Tab S9 FE — o FP32 carrega e roda no mesmo aparelho. O INT8 completo funcionaria,
> mas devolve a saída crua `[1,5,336]` e exigiria implementar NMS em Dart.

**Desempenho** (Galaxy Tab S9 FE, build profile, 480p). Tudo abaixo foi medido no
aparelho, por estágio — nenhum número é estimativa:

| | antes | depois | o que mudou |
|---|---|---|---|
| inferência de pupila | 68,2 ms | **24,8 ms** | ler/escrever nos buffers tipados em vez de listas aninhadas (a inferência nativa sempre foi 15 ms; o resto era *marshalling*) |
| Face Mesh por quadro | 150 ms (720p) | **28 ms** | 480p + reaproveitar os cantos por 3 quadros |
| taxa com rosto | 4–6 fps | **10–12 fps** | as duas acima |
| rosto encontrado | 0 de 30 quadros | **100%** | rotação (abaixo) |
| pupilas por quadro | 0 | **2,00** | idem |

O gargalo **não** era o modelo. Meça por estágio antes de otimizar.

### A rotação é o que faz o Face Mesh funcionar

Passar o `sensorOrientation` cru falha num tablet em paisagem: o ML Kit procura o rosto
numa imagem girada, e não acha em quase nenhum quadro. A rotação correta soma a
orientação da tela (frontal) ou subtrai (traseira) — `rotationDegreesFor()`, travada por
teste. No Tab S9 FE: sensor 270° + paisagem 90° = **0°**, não 270°.

O **mesmo** valor tem de alimentar o ML Kit e a amostragem do recorte; se divergirem, os
landmarks e o recorte passam a viver em espaços diferentes e nada acusa o erro.
`assets/models/crop_params.json` carrega a geometria usada no treino — os dois **têm de
andar juntos**.

**Ainda não verificado em aparelho.** Testes cobrem geometria, ajuste, rotação e zonas,
e o APK compila com o modelo e as libs nativas empacotados. O que só um tablet resolve:
o espelhamento da câmera frontal e a orientação do sensor.
