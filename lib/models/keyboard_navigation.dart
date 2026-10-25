import 'gaze_command.dart';
import 'keyboard_layout.dart';

/// Navegação pelas setas no teclado, com as regras da tela: mudar de linha
/// limita a coluna ao tamanho da linha de destino.
///
/// Usada pela linha de base de TypingMetrics, pelo digitador simulado da
/// avaliação offline e pelo WordPredictor (teclas vizinhas para tolerar erros
/// de digitação), para que todos sigam a mesma regra.
class KeyboardNavigation {
  KeyboardNavigation(this.layout);

  final List<List<KeyDef>> layout;

  /// Linha e coluna da tecla com [label].
  (int, int) find(String label) {
    for (var r = 0; r < layout.length; r++) {
      for (var c = 0; c < layout[r].length; c++) {
        if (layout[r][c].label == label) return (r, c);
      }
    }
    throw ArgumentError('Tecla inexistente: $label');
  }

  /// Rótulos das teclas a uma seta de distância da tecla [label].
  Set<String> neighbors(String label) {
    final from = find(label);
    return {
      for (final (_, (r, c)) in _moves(from))
        if ((r, c) != from) layout[r][c].label,
    };
  }

  /// Caminho mínimo de setas entre duas teclas (busca em largura).
  List<GazeCommand> path((int, int) from, (int, int) to) {
    final previous = <(int, int), ((int, int), GazeCommand)?>{from: null};
    final queue = [from];
    for (var i = 0; i < queue.length && !previous.containsKey(to); i++) {
      for (final (command, next) in _moves(queue[i])) {
        if (previous.containsKey(next)) continue;
        previous[next] = (queue[i], command);
        queue.add(next);
      }
    }
    if (!previous.containsKey(to)) throw StateError('Tecla inalcançável: $to');
    final path = <GazeCommand>[];
    for (var step = previous[to]; step != null; step = previous[step.$1]) {
      path.add(step.$2);
    }
    return path.reversed.toList();
  }

  /// Onde cada seta leva a partir de [position].
  Iterable<(GazeCommand, (int, int))> _moves((int, int) position) sync* {
    final (row, column) = position;
    for (final (command, dr, dc) in const [
      (GazeCommand.up, -1, 0),
      (GazeCommand.down, 1, 0),
      (GazeCommand.left, 0, -1),
      (GazeCommand.right, 0, 1),
    ]) {
      final r = (row + dr).clamp(0, layout.length - 1);
      yield (command, (r, (column + dc).clamp(0, layout[r].length - 1)));
    }
  }
}
