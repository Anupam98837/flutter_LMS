import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:msitlms/app/app_keys.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Transparent status bar so the app bleeds into it naturally
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const LoginPage(),
    );
  }
}

/// A helper for smooth slide+fade navigation from anywhere in the app.
///
/// Usage: Navigator.of(context).push(smoothRoute(MyPage()))
Route<T> smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(opacity: curve, child: child),
      );
    },
  );
}
