import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://dbrbufzvahscmipqinpq.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRicmJ1Znp2YWhzY21pcHFpbnBxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0NjEzNjgsImV4cCI6MjA4NTAzNzM2OH0.yZ6HU-0FKD2SeX-uWP-ogdsociSWl2Yv0OSwQ-K5UvY',
  );

  runApp(const ShogyoMujoApp());
}

class ShogyoMujoApp extends StatelessWidget {
  const ShogyoMujoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '諸行無常ログ',
      theme: ThemeData(primarySwatch: Colors.orange),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final session = snapshot.data!.session;

          if (session == null) {
            return const LoginScreen();
          } else {
            return const HomeScreen();
          }
        },
      ),
    );
  }
}
