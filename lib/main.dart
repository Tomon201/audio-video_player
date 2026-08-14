import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'providers/media_provider.dart';
import 'services/database_service.dart';
import 'screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background audio support
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.ytmusic.channel.audio',
    androidNotificationChannelName: 'YT Music Player',
    androidNotificationOngoing: true,
  );

  // Initialize SQLite database instance for future playlists
  await AppDatabase.instance.database;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MediaProvider()..requestPermissionAndScan()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Music & Video Offline Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.redAccent,
          surface: Color(0xFF212121),
        ),
      ),
      home: const MainScreen(),
    );
  }
}