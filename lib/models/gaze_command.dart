/// Comandos de navegação da interface.
///
/// As setas na tela emitem exatamente estes comandos, e o módulo de eye
/// tracking deverá emitir os mesmos — assim a troca do controle manual pelo
/// olhar não exige mudança na UI.
enum GazeCommand { up, down, left, right, select }
