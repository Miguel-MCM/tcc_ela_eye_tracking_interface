/// Arranjo geométrico das setas de navegação.
///
/// Existem dois porque a melhor geometria para eye tracking é uma questão
/// empírica: depende do rastreador, da distância da tela e do próprio usuário.
/// Manter os dois permite medir a taxa de acerto de cada um com o paciente
/// real em vez de decidir no chute.
enum ControlStyle {
  /// Setas nas quatro bordas da tela. Máxima separação angular entre os
  /// alvos, ao custo do espaço das bordas.
  edges,

  /// Cruz compacta ao lado do teclado. Ocupa menos área, mas os alvos ficam
  /// próximos uns dos outros.
  cross,
}
