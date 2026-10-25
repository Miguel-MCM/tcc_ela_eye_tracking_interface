// Avaliação offline do autocomplete sobre o corpus de frases do app.
//
// Uso (na raiz do projeto):
//   dart run tool/evaluate_predictor.dart
//   dart run tool/evaluate_predictor.dart --json resultados.json
//
// Imprime uma tabela em Markdown com os cenários: o digitador sem erros; com
// 10% de letras trocadas por vizinhas e notadas só no fim da palavra, sem e
// com a tolerância a erros do preditor; e a avaliação nas próprias frases de
// treino (só como referência). Ver lib/metrics/predictor_evaluation.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tcc_ela_eye_tracking_interface/metrics/predictor_evaluation.dart';
import 'package:tcc_ela_eye_tracking_interface/models/word_predictor.dart';

Future<void> main(List<String> args) async {
  final phrases = await WordPredictor.loadPhrases(
    (path) => File(path).readAsString(),
  );
  final unique = deduplicate(phrases).length;
  SimulatedTypist withErrors(WordPredictor predictor) => SimulatedTypist(
    predictor,
    errorRate: 0.1,
    noticesErrors: false,
    random: Random(7),
  );
  final scenarios = <String, EvaluationResult>{
    'Sem erros (validação cruzada)': crossValidate(phrases),
    '10% de erros, sem tolerância': crossValidate(
      phrases,
      model: (train) => WordPredictor(phrases: train, typoMaxCost: 0),
      typist: withErrors,
    ),
    '10% de erros, com tolerância': crossValidate(phrases, typist: withErrors),
    'Nas frases de treino (referência)': evaluateInSample(phrases),
  };

  stdout
    ..writeln(
      'Corpus: ${phrases.length} frases, '
      '$unique após remover repetidas.',
    )
    ..writeln('Validação cruzada em 10 partes, semente 42, 3 sugestões.')
    ..writeln()
    ..writeln('| Métrica | ${scenarios.keys.join(' | ')} |')
    ..writeln('|---|${'---|' * scenarios.length}');

  String percent(double? v) =>
      v == null ? '-' : '${(v * 100).toStringAsFixed(1)}%';
  String number(double? v) => v == null ? '-' : v.toStringAsFixed(2);
  final rows = <String, String Function(EvaluationResult)>{
    'Frases / palavras': (r) => '${r.phrases} / ${r.words}',
    'Palavras fora do vocabulário de treino': (r) =>
        percent(r.outOfVocabularyRate),
    'Economia de comandos (navegação + seleção)': (r) =>
        percent(r.counts.keystrokeSavings),
    'Economia de seleções': (r) => percent(r.counts.keystrokeSavingsSelections),
    'Comandos por caractere (KSPC)': (r) => number(r.counts.kspc),
    'Seleções por caractere': (r) => number(r.counts.kspcSelections),
    'Palavras previstas em 1º lugar': (r) =>
        percent(r.counts.predictionAccuracyTop1),
    'Palavras previstas entre as 3': (r) =>
        percent(r.counts.predictionAccuracy),
    'Letras digitadas antes da previsão (média)': (r) =>
        number(r.counts.meanCharactersBeforePrediction),
    'Palavras inseridas por sugestão': (r) => percent(r.counts.completionRate),
    'WPM estimado (1,5 s por comando)': (r) => number(r.counts.wordsPerMinute),
  };
  rows.forEach((name, cell) {
    stdout.writeln('| $name | ${scenarios.values.map(cell).join(' | ')} |');
  });

  final jsonIndex = args.indexOf('--json');
  if (jsonIndex >= 0 && jsonIndex + 1 < args.length) {
    final out = {
      'corpusPhrases': phrases.length,
      'uniquePhrases': unique,
      'folds': 10,
      'seed': 42,
      'scenarios': {
        for (final MapEntry(:key, :value) in scenarios.entries)
          key: {
            'phrases': value.phrases,
            'words': value.words,
            'outOfVocabulary': value.outOfVocabulary,
            ...value.counts.toJson(),
          },
      },
    };
    await File(
      args[jsonIndex + 1],
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    stdout.writeln('\nJSON gravado em ${args[jsonIndex + 1]}');
  }
}
