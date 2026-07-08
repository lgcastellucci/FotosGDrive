import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/album_config_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';

/// Primeira tela que o usuário vê ao abrir o app pela primeira vez.
///
/// Fluxo: 1) entrar com a conta Google (mesmo mecanismo de sempre);
/// 2) digitar o nome do álbum de fotos que o app vai criar/monitorar.
/// Esse nome é usado tanto para o álbum local no dispositivo quanto
/// para a pasta correspondente no Google Drive. Uma vez configurado,
/// o app não pergunta de novo — vai direto para a tela principal.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final AuthService _authService = AuthService();
  final AlbumConfigService _configService = AlbumConfigService();
  final TextEditingController _albumController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _authenticated = false;
  bool _authenticating = false;
  bool _saving = false;
  String? _authError;

  @override
  void initState() {
    super.initState();
    _tryRestoreSession();
  }

  Future<void> _tryRestoreSession() async {
    final restored = await _authService.tryRestoreSession();
    if (restored && mounted) {
      setState(() => _authenticated = true);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _authenticating = true;
      _authError = null;
    });
    try {
      final ok = await _authService.signIn();
      setState(() {
        _authenticated = ok;
        if (!ok) _authError = 'Login cancelado. Tente novamente.';
      });
    } catch (e) {
      setState(() => _authError = 'Falha ao entrar com o Google: $e');
    } finally {
      setState(() => _authenticating = false);
    }
  }

  Future<void> _confirmAlbum() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final albumName = _albumController.text.trim();
    await _configService.setAlbumName(albumName);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          albumName: albumName,
          authService: _authService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _albumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.blue700,
                          Color(0xFF1976D2),
                          AppColors.blue500
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.blue700.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('🖼️', style: TextStyle(fontSize: 34)),
                  ),
                  const SizedBox(height: 18),
                  Text('FotosGDrive',
                      style: GoogleFonts.dmSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gray900)),
                  const SizedBox(height: 6),
                  Text(
                    'Escolha um álbum de fotos no seu celular e mande\ntudo para uma pasta com o mesmo nome no Drive.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.gray400, height: 1.4),
                  ),
                  const SizedBox(height: 28),

                  // Passo 1 — login no Google
                  _StepCard(
                    stepNumber: 1,
                    title: 'Conecte sua conta Google',
                    done: _authenticated,
                    child: _authenticated
                        ? Row(
                            children: [
                              const Text('🟢', style: TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _authService.userEmail ?? 'Conta conectada',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.gray900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                onPressed: _authenticating ? null : _signIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.blue700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(_authenticating
                                    ? 'Conectando...'
                                    : '🔐  Entrar com Google'),
                              ),
                              if (_authError != null) ...[
                                const SizedBox(height: 8),
                                Text(_authError!,
                                    style: GoogleFonts.dmSans(
                                        fontSize: 12, color: AppColors.red)),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Passo 2 — nome do álbum
                  _StepCard(
                    stepNumber: 2,
                    title: 'Nome do álbum de fotos',
                    done: false,
                    enabled: _authenticated,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _albumController,
                            enabled: _authenticated && !_saving,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              hintText: 'Ex.: Viagem 2026, Aniversário...',
                              filled: true,
                              fillColor: AppColors.gray100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                            validator: (value) {
                              final v = value?.trim() ?? '';
                              if (v.isEmpty) {
                                return 'Digite um nome para o álbum';
                              }
                              if (v.length > 80) {
                                return 'Nome muito longo (máx. 80 caracteres)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Esse será o nome do álbum no celular e da pasta criada no Google Drive.',
                            style: GoogleFonts.dmSans(
                                fontSize: 11, color: AppColors.gray400),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed:
                                _authenticated && !_saving ? _confirmAlbum : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.blue700,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.gray100,
                              disabledForegroundColor: AppColors.gray400,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                                _saving ? 'Criando álbum...' : '✅  Criar álbum e continuar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int stepNumber;
  final String title;
  final bool done;
  final bool enabled;
  final Widget child;

  const _StepCard({
    required this.stepNumber,
    required this.title,
    required this.done,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done
                ? const Color(0xFFC8E6C9)
                : Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.blue900.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: done ? AppColors.green : AppColors.blue50,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('$stepNumber',
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.blue700)),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: GoogleFonts.dmSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gray900)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
