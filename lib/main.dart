import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final config = AppConfig();
  await config.load();

  final auth = AuthService(config);
  await auth.tryAutoLogin();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: config),
        ChangeNotifierProvider.value(value: auth),
        ProxyProvider2<AppConfig, AuthService, ApiService>(
          update: (_, cfg, a, __) => ApiService(cfg, a),
        ),
      ],
      child: const TafrighApp(),
    ),
  );
}

class TafrighApp extends StatelessWidget {
  const TafrighApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        return MaterialApp(
          title: 'التفريغ',
          debugShowCheckedModeBanner: false,
          theme: _darkTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
        );
      },
    );
  }

  ThemeData _darkTheme() {
    const bg     = Color(0xFF060B14);
    const surf   = Color(0xFF0B1423);
    const surf2  = Color(0xFF0F1C30);
    const border = Color(0xFF1A2D45);
    const sky    = Color(0xFF0EA5E9);
    const cyan   = Color(0xFF06B6D4);
    const text   = Color(0xFFD8E4F0);
    const dim    = Color(0xFF6B7F96);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:   sky,
        secondary: cyan,
        surface:   surf,
        onSurface: text,
        outline:   border,
      ),
      scaffoldBackgroundColor: bg,
      cardColor: surf,
      dividerColor: border,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: text),
        bodySmall:  TextStyle(color: dim),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surf,
        foregroundColor: text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: text, fontSize: 17, fontWeight: FontWeight.bold,
          fontFamily: 'sans-serif',
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surf2,
        border:         OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: border)),
        enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: border)),
        focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: sky, width: 1.5)),
        labelStyle: const TextStyle(color: dim),
        hintStyle:  const TextStyle(color: dim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: sky,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: sky,
          side: const BorderSide(color: sky),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surf2,
        selectedColor: sky.withOpacity(0.2),
        labelStyle: const TextStyle(color: text, fontSize: 13),
        side: const BorderSide(color: border),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surf2,
        contentTextStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
