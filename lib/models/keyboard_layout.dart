/// Tipo de ação de uma tecla.
enum KeyAction { character, space, backspace, clear }

/// Uma tecla do teclado na tela.
class KeyDef {
  const KeyDef.character(this.label)
      : action = KeyAction.character,
        flex = 1;

  const KeyDef.special(this.label, this.action, {this.flex = 1});

  final String label;
  final KeyAction action;

  /// Peso da tecla na linha — teclas especiais ocupam mais espaço.
  final int flex;

  bool get isCharacter => action == KeyAction.character;
}

/// Layout QWERTY com uma linha final de teclas de edição.
///
/// As linhas têm comprimentos diferentes; a navegação trata disso limitando a
/// coluna ao tamanho da linha de destino.
const List<List<KeyDef>> kKeyboardRows = [
  [
    KeyDef.character('Q'),
    KeyDef.character('W'),
    KeyDef.character('E'),
    KeyDef.character('R'),
    KeyDef.character('T'),
    KeyDef.character('Y'),
    KeyDef.character('U'),
    KeyDef.character('I'),
    KeyDef.character('O'),
    KeyDef.character('P'),
  ],
  [
    KeyDef.character('A'),
    KeyDef.character('S'),
    KeyDef.character('D'),
    KeyDef.character('F'),
    KeyDef.character('G'),
    KeyDef.character('H'),
    KeyDef.character('J'),
    KeyDef.character('K'),
    KeyDef.character('L'),
  ],
  [
    KeyDef.character('Z'),
    KeyDef.character('X'),
    KeyDef.character('C'),
    KeyDef.character('V'),
    KeyDef.character('B'),
    KeyDef.character('N'),
    KeyDef.character('M'),
  ],
  [
    KeyDef.special('ESPAÇO', KeyAction.space, flex: 3),
    KeyDef.special('APAGAR', KeyAction.backspace, flex: 2),
    KeyDef.special('LIMPAR', KeyAction.clear, flex: 2),
  ],
];
