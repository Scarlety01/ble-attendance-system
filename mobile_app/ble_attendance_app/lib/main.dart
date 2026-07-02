import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient().init();
  runApp(const BleAttendanceApp());
}

class BleAttendanceApp extends StatelessWidget {
  const BleAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BLE Attendance',

      // iPhone dark mode байсан ч app-ийг light болгож хүчээр ажиллуулна.
      themeMode: ThemeMode.light,
      theme: AppTheme.lightTheme(),

      // Зарим widget system dark mode-оос өнгө авахыг хаана.
      darkTheme: AppTheme.lightTheme(),

      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();

  late final Future<bool> _hasTokenFuture = _authService.hasToken();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasTokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final hasToken = snapshot.data == true;
        return hasToken ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
