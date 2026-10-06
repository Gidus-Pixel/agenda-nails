import 'package:flutter/material.dart';

void main() => runApp(const AppProva());

class AppProva extends StatelessWidget {
  const AppProva({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Text('Agenda', style: TextStyle(fontFamily: 'Fraunces', fontSize: 40)))),
      );
}
