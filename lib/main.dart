import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/onboarding_page.dart';
import 'services/album_config_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const FotosGDriveApp());
}

class FotosGDriveApp extends StatelessWidget {
  const FotosGDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FotosGDrive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppRoot(),
    );
  }
}

/// Decide, ao abrir o app, se mostra o onboarding (primeiro acesso —
/// ainda não existe um álbum configurado) ou a tela principal
/// (o usuário já escolheu um álbum em uma execução anterior).
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final AlbumConfigService _configService = AlbumConfigService();
  bool _loading = true;
  String? _albumName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await _configService.getAlbumName();
    if (!mounted) return;
    setState(() {
      _albumName = name;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_albumName == null) {
      return const OnboardingPage();
    }
    return HomePage(albumName: _albumName!);
  }
}
