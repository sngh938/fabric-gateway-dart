import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fabric Gateway Example',
      home: Scaffold(
        appBar: AppBar(title: const Text('Fabric Gateway Example')),
        body: const Center(child: Text('Example app skeleton')),
      ),
    );
  }
}
