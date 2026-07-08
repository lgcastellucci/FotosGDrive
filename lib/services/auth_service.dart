import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Escopo mínimo necessário: acesso apenas aos arquivos criados pelo
/// próprio app no Drive (não enxerga o Drive inteiro do usuário).
const List<String> kDriveScopes = [
  'https://www.googleapis.com/auth/drive.file',
];

/// http.Client que injeta o header Authorization do Google Sign-In
/// em toda requisição. É isso que a googleapis DriveApi precisa para
/// autenticar as chamadas REST.
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  void close() => _inner.close();
}

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: kDriveScopes);

  GoogleSignInAccount? _currentUser;

  bool get isAuthenticated => _currentUser != null;
  String? get userEmail => _currentUser?.email;

  /// Tenta restaurar sessão silenciosamente (token salvo pelo próprio
  /// plugin google_sign_in). Retorna true se já autenticado.
  Future<bool> tryRestoreSession() async {
    final account = await _googleSignIn.signInSilently();
    if (account != null) {
      _currentUser = account;
      return true;
    }
    return false;
  }

  /// Abre o seletor de contas do Google (SDK nativo do Android).
  Future<bool> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      // Usuário cancelou o fluxo.
      return false;
    }
    _currentUser = account;
    return true;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  /// Client HTTP autenticado, pronto para ser passado ao DriveApi.
  /// Renova os headers a cada chamada para evitar token expirado
  /// em uploads longos (várias fotos em sequência).
  Future<GoogleAuthClient> getAuthenticatedClient() async {
    if (_currentUser == null) {
      throw StateError('Usuário não autenticado no Google.');
    }
    final headers = await _currentUser!.authHeaders;
    return GoogleAuthClient(headers);
  }
}
