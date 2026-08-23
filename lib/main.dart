import 'package:flutter/material.dart';

import 'screens/communicator_screen.dart';

void main() {
  runApp(const ElaCommunicatorApp());
}

class ElaCommunicatorApp extends StatelessWidget {
  const ElaCommunicatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comunicador ELA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Tema escuro e de alto contraste: a tela costuma ficar próxima do
        // rosto do paciente por longos períodos.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CommunicatorScreen(),
    );
  }
}
