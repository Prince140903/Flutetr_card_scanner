import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/websocket_provider.dart';
import 'screens/camera_screen.dart';
import 'screens/landing_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WebSocketProvider(),
      child: MaterialApp(
        title: 'ID Card Scanner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        home: const LandingScreen(),
        routes: {
          '/landing': (context) => const LandingScreen(),
          '/camera': (context) => const CameraScreen(),
        },
      ),
    );
  }
}
