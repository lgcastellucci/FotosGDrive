import 'package:shared_preferences/shared_preferences.dart';

/// Guarda o nome do álbum escolhido pelo usuário no primeiro acesso.
///
/// Esse mesmo nome é usado tanto para localizar o álbum de fotos no
/// dispositivo quanto para nomear a pasta correspondente no Google
/// Drive — não existe mais um álbum fixo ("Escola"): quem decide o
/// nome é o usuário, uma única vez, e o app lembra disso entre uma
/// abertura e outra.
class AlbumConfigService {
  static const String _kAlbumNameKey = 'album_name';

  /// Retorna o nome do álbum já configurado, ou null se essa ainda é
  /// a primeira execução do app (nenhum álbum foi escolhido ainda).
  Future<String?> getAlbumName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kAlbumNameKey);
    if (name == null || name.trim().isEmpty) return null;
    return name;
  }

  /// Salva o nome do álbum escolhido pelo usuário.
  Future<void> setAlbumName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAlbumNameKey, name.trim());
  }

  /// Limpa a configuração — usado se o usuário quiser trocar de álbum
  /// e passar pelo fluxo de escolha novamente.
  Future<void> clearAlbumName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAlbumNameKey);
  }
}
