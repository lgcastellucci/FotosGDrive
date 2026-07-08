import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/log_entry.dart';
import '../models/photo_item.dart';
import '../services/album_config_service.dart';
import '../services/auth_service.dart';
import '../services/drive_service.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';
import '../utils/mime_utils.dart';
import 'onboarding_page.dart';

class HomePage extends StatefulWidget {
  /// Nome do álbum escolhido pelo usuário no primeiro acesso — usado
  /// tanto para localizar o álbum de fotos no dispositivo quanto para
  /// nomear a pasta correspondente no Google Drive.
  final String albumName;

  /// AuthService já autenticado, vindo do onboarding (evita pedir
  /// login de novo logo após o usuário acabar de entrar). Se null,
  /// um novo é criado e o app tenta restaurar a sessão salva.
  final AuthService? authService;

  const HomePage({super.key, required this.albumName, this.authService});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _RunState { idle, running, done }

class _HomePageState extends State<HomePage> {
  late final AuthService _authService = widget.authService ?? AuthService();
  late final DriveService _driveService =
      DriveService(_authService, folderName: widget.albumName);
  late final MediaService _mediaService =
      MediaService(albumName: widget.albumName);
  final AlbumConfigService _configService = AlbumConfigService();

  final List<LogEntry> _logs = [];
  final ScrollController _logScroll = ScrollController();
  final _timeFmt = DateFormat('HH:mm:ss');

  bool _authenticated = false;
  bool _showTechnicalLog = false;
  _RunState _runState = _RunState.idle;

  int _albumCount = 0; // fotos encontradas no álbum ao autenticar
  int _total = 0;
  int _done = 0;
  int _uploaded = 0;
  int _deleted = 0;
  int _failed = 0;
  String? _currentFileName;

  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _log('App iniciado', LogLevel.success);
    _loadVersion();
    if (widget.authService != null && _authService.isAuthenticated) {
      // Já veio autenticado da tela de configuração inicial.
      _authenticated = true;
      _log('Autenticado no Google Drive', LogLevel.success);
      _refreshAlbumCount();
    } else {
      _restoreSession();
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _versionLabel = 'v${info.version} (build ${info.buildNumber})');
      }
    } catch (_) {
      // Não crítico — só não mostra a versão.
    }
  }

  Future<void> _restoreSession() async {
    final restored = await _authService.tryRestoreSession();
    if (restored) {
      setState(() => _authenticated = true);
      _log('Sessão do Google restaurada', LogLevel.success);
      _refreshAlbumCount();
    }
  }

  Future<void> _refreshAlbumCount() async {
    final granted = await _mediaService.requestPermission();
    if (!granted) return;
    await _mediaService.ensureControlPhoto();
    final photos = await _mediaService.listPhotosInAlbum();
    if (mounted) setState(() => _albumCount = photos.length);
  }

  void _log(String message, [LogLevel level = LogLevel.info]) {
    setState(() => _logs.add(LogEntry(message: message, level: level)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _authenticate() async {
    _log('Autenticando no Google...', LogLevel.warning);
    try {
      final ok = await _authService.signIn();
      if (ok) {
        setState(() => _authenticated = true);
        _log('Autenticado no Google Drive', LogLevel.success);
        _refreshAlbumCount();
      } else {
        _log('Login cancelado pelo usuário', LogLevel.warning);
      }
    } catch (e) {
      _log('Falha ao autenticar: $e', LogLevel.error);
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    setState(() {
      _authenticated = false;
      _albumCount = 0;
    });
    _log('Sessão encerrada', LogLevel.info);
  }

  Future<void> _changeAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trocar de álbum?'),
        content: Text(
          'Isso não apaga fotos nem arquivos já enviados — só faz o '
          'app esquecer que "${widget.albumName}" é o álbum atual, '
          'para você escolher outro nome.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trocar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _configService.clearAlbumName();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingPage()),
      (route) => false,
    );
  }

  Future<void> _sendNow() async {
    if (!_authenticated) {
      _log('Autentique-se no Google antes de enviar', LogLevel.error);
      return;
    }
    if (_runState == _RunState.running) return;

    setState(() {
      _runState = _RunState.running;
      _total = 0;
      _done = 0;
      _uploaded = 0;
      _deleted = 0;
      _failed = 0;
      _currentFileName = null;
    });

    try {
      _log('Verificando permissão de acesso às fotos...', LogLevel.warning);
      final granted = await _mediaService.requestPermission();
      if (!granted) {
        _log('Permissão de fotos negada', LogLevel.error);
        setState(() => _runState = _RunState.idle);
        return;
      }
      await _mediaService.ensureControlPhoto();

      _log('Buscando fotos no álbum "${widget.albumName}"...', LogLevel.warning);
      final photos = await _mediaService.listPhotosInAlbum();
      _log('${photos.length} foto(s) encontrada(s)',
          photos.isEmpty ? LogLevel.warning : LogLevel.success);

      setState(() {
        _albumCount = photos.length;
        _total = photos.length;
      });

      if (photos.isEmpty) {
        setState(() => _runState = _RunState.done);
        return;
      }

      _log('Garantindo pasta "${widget.albumName}" no Drive...', LogLevel.warning);
      final folderId = await _driveService.ensureFolder();
      _log('Pasta "${widget.albumName}" pronta no Drive', LogLevel.success);

      final uploaded = <PhotoItem>[];

      for (final photo in photos) {
        setState(() => _currentFileName = photo.name);
        _log('Upload ${photo.name}...', LogLevel.warning);
        try {
          final exists = await _driveService.fileExists(photo.name, folderId);
          if (exists) {
            _log('${photo.name} já existe no Drive — pulando', LogLevel.info);
            setState(() => _done++);
            continue;
          }

          final file = await photo.asset.file;
          if (file == null) {
            _log('${photo.name}: não foi possível ler o arquivo local',
                LogLevel.error);
            setState(() {
              _done++;
              _failed++;
            });
            continue;
          }

          final fileId = await _driveService.uploadFile(
            localFile: file,
            fileName: photo.name,
            folderId: folderId,
            mimeType: resolveMimeType(photo.name),
          );

          photo.driveFileId = fileId;
          photo.status = UploadStatus.uploaded;
          uploaded.add(photo);

          _log('${photo.name} → Drive OK', LogLevel.success);
          setState(() => _uploaded++);
        } catch (e) {
          photo.status = UploadStatus.error;
          photo.errorMessage = e.toString();
          _log('Erro no upload de ${photo.name}: $e', LogLevel.error);
          setState(() => _failed++);
        }
        setState(() => _done++);
      }

      if (uploaded.isNotEmpty) {
        _log(
            'Excluindo ${uploaded.length} foto(s) do dispositivo (upload confirmado)...',
            LogLevel.warning);
        try {
          final deletedIds = await _mediaService.deletePhotos(uploaded);
          setState(() => _deleted = deletedIds.length);
          _log('${deletedIds.length} foto(s) deletada(s) do dispositivo',
              LogLevel.success);
        } catch (e) {
          _log('Erro ao deletar fotos localmente: $e', LogLevel.error);
        }
      }

      _log('Sincronização concluída', LogLevel.success);
      _refreshAlbumCount();
    } catch (e) {
      _log('Erro inesperado: $e', LogLevel.error);
    } finally {
      setState(() => _runState = _RunState.done);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FotosGDrive'),
        actions: [
          IconButton(
            tooltip: 'Trocar álbum',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _runState == _RunState.running ? null : _changeAlbum,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _HeaderCard(compact: _authenticated),
            const SizedBox(height: 8),
            _AccountCard(
              authenticated: _authenticated,
              email: _authService.userEmail,
              busy: _runState == _RunState.running,
              onSignIn: _authenticate,
              onSignOut: _signOut,
            ),
            const SizedBox(height: 8),
            _AlbumCard(
              authenticated: _authenticated,
              albumCount: _albumCount,
              albumName: widget.albumName,
            ),
            const SizedBox(height: 8),
            if (_runState == _RunState.running) ...[
              _ProgressCard(
                total: _total,
                done: _done,
                currentFileName: _currentFileName,
              ),
              const SizedBox(height: 8),
              const _StatusPill(
                icon: '📡',
                text: 'Conectado ao Drive — não feche o app',
                kind: _PillKind.info,
              ),
              const SizedBox(height: 8),
            ],
            if (_runState == _RunState.done) ...[
              _ResultCard(
                uploaded: _uploaded,
                deleted: _deleted,
                failed: _failed,
              ),
              const SizedBox(height: 8),
            ],
            _SendButton(
              state: _runState,
              enabled: _authenticated,
              onPressed: _sendNow,
            ),
            const SizedBox(height: 8),
            const _WarningBox(),
            const SizedBox(height: 14),
            _TechnicalLogSection(
              expanded: _showTechnicalLog,
              onToggle: () =>
                  setState(() => _showTechnicalLog = !_showTechnicalLog),
              logs: _logs,
              scrollController: _logScroll,
              timeFmt: _timeFmt,
            ),
            const SizedBox(height: 14),
            if (_versionLabel.isNotEmpty)
              Center(
                child: Text(
                  'FotosGDrive $_versionLabel',
                  style: AppTheme.mono(size: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────
// Widgets de apoio
// ─────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final bool compact;
  const _HeaderCard({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 18,
        vertical: compact ? 12 : 18,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue700, Color(0xFF1976D2), AppColors.blue500],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue700.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: compact
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📚', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text('FotosGDrive',
                    style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            )
          : Column(
              children: [
                const Text('📚', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                Text('FotosGDrive',
                    style: GoogleFonts.dmSans(
                        fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 2),
                Text('Mova fotos do álbum para o Google Drive',
                    style: GoogleFonts.dmSans(
                        fontSize: 11.5, color: Colors.white.withValues(alpha: 0.75))),
              ],
            ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  final String text;
  const _CardLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.dmSans(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.gray400,
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  const _CardShell({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue900.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AccountCard extends StatelessWidget {
  final bool authenticated;
  final String? email;
  final bool busy;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  const _AccountCard({
    required this.authenticated,
    required this.email,
    required this.busy,
    required this.onSignIn,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Conta Google Drive'),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: authenticated ? AppColors.greenBg : AppColors.blue50,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(authenticated ? '🟢' : '👤',
                    style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  authenticated
                      ? (email ?? 'Conta conectada')
                      : 'Nenhuma conta conectada',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: authenticated ? AppColors.gray900 : AppColors.gray400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (authenticated)
                TextButton(
                  onPressed: busy ? null : onSignOut,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Sair', style: TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
          if (!authenticated) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: busy ? null : onSignIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('🔐  Entrar com Google'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final bool authenticated;
  final int albumCount;
  final String albumName;
  const _AlbumCard({
    required this.authenticated,
    required this.albumCount,
    required this.albumName,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Álbum de origem'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('📷  $albumName',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.gray900),
                      overflow: TextOverflow.ellipsis),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: authenticated
                            ? AppColors.blue500
                            : AppColors.gray400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      authenticated ? '$albumCount foto(s)' : 'Faça login',
                      style: GoogleFonts.dmSans(
                          fontSize: 11.5, color: AppColors.gray400),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.blue50,
              border: Border.all(color: AppColors.blue200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('📁', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DESTINO NO DRIVE',
                          style: GoogleFonts.dmSans(
                              fontSize: 9.5, color: AppColors.gray400)),
                      Text('Google Drive → pasta "$albumName"',
                          style: GoogleFonts.dmSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.blue700),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int total;
  final int done;
  final String? currentFileName;

  const _ProgressCard({
    required this.total,
    required this.done,
    required this.currentFileName,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    final pct = (progress * 100).round();
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '⬆ Enviando foto ${done + 1 > total ? total : done + 1}/$total…',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.gray400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('$pct%',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600, color: AppColors.blue700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.gray100,
              valueColor: const AlwaysStoppedAnimation(AppColors.blue500),
            ),
          ),
          if (currentFileName != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                currentFileName!,
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.gray400),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PillKind { success, info, warning }

class _StatusPill extends StatelessWidget {
  final String icon;
  final String text;
  final _PillKind kind;
  const _StatusPill({required this.icon, required this.text, required this.kind});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (kind) {
      case _PillKind.success:
        bg = AppColors.greenBg;
        fg = AppColors.green;
        break;
      case _PillKind.info:
        bg = AppColors.blue50;
        fg = AppColors.blue700;
        break;
      case _PillKind.warning:
        bg = AppColors.amberBg;
        fg = AppColors.amber;
        break;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final int uploaded;
  final int deleted;
  final int failed;
  const _ResultCard({
    required this.uploaded,
    required this.deleted,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      borderColor: const Color(0xFFC8E6C9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✅', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Envio concluído!',
                  style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.green)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _StatBox(value: uploaded, label: 'Enviadas', color: AppColors.blue50, valueColor: AppColors.blue700)),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(value: deleted, label: 'Removidas', color: AppColors.greenBg, valueColor: AppColors.green)),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(value: failed, label: 'Falhas', color: AppColors.amberBg, valueColor: AppColors.amber)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final Color valueColor;
  const _StatBox({
    required this.value,
    required this.label,
    required this.color,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text('$value',
              style: GoogleFonts.dmSans(
                  fontSize: 20, fontWeight: FontWeight.w700, color: valueColor)),
          Text(label,
              style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.gray400)),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final _RunState state;
  final bool enabled;
  final VoidCallback onPressed;
  const _SendButton({required this.state, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final running = state == _RunState.running;
    final active = enabled && !running;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: active
              ? const LinearGradient(colors: [AppColors.blue700, Color(0xFF1976D2)])
              : null,
          color: active ? null : AppColors.gray100,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.blue700.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: active ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  running ? '📤  Enviando…' : '📤  Enviar Agora',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.gray400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        border: Border.all(color: const Color(0xFFFFE082)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(
              fontSize: 11.5, color: const Color(0xFF5D4037), height: 1.4),
          children: const [
            TextSpan(text: '⚠ As fotos serão '),
            TextSpan(
                text: 'removidas do celular',
                style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
                text: ' somente após confirmação de upload bem-sucedido no Drive.'),
          ],
        ),
      ),
    );
  }
}

/// Log técnico — mantido para acompanhar o processo em detalhe (útil
/// pra depuração), mas discreto e recolhido por padrão, sem dominar a
/// tela como no visual anterior.
class _TechnicalLogSection extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final List<LogEntry> logs;
  final ScrollController scrollController;
  final DateFormat timeFmt;

  const _TechnicalLogSection({
    required this.expanded,
    required this.onToggle,
    required this.logs,
    required this.scrollController,
    required this.timeFmt,
  });

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.success:
        return AppColors.green;
      case LogLevel.error:
        return AppColors.red;
      case LogLevel.warning:
        return AppColors.amber;
      case LogLevel.info:
        return AppColors.blue700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: AppColors.gray400),
              const SizedBox(width: 4),
              Text('Detalhes técnicos do processo',
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.gray400)),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          Container(
            height: 180,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: ListView.builder(
              controller: scrollController,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final entry = logs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: AppTheme.mono(size: 11),
                      children: [
                        TextSpan(text: '${entry.icon} ${timeFmt.format(entry.timestamp)}  '),
                        TextSpan(
                          text: entry.message,
                          style: TextStyle(color: _levelColor(entry.level)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
