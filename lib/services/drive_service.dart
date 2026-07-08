import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;

import 'auth_service.dart';

class DriveService {
  final AuthService authService;

  /// Nome da pasta a criar/usar no Google Drive — é o mesmo nome do
  /// álbum escolhido pelo usuário no primeiro acesso ao app.
  final String folderName;

  String? _folderId;

  DriveService(this.authService, {required this.folderName});

  Future<drive.DriveApi> _api() async {
    final client = await authService.getAuthenticatedClient();
    return drive.DriveApi(client);
  }

  /// Retorna o ID da pasta do álbum no Drive, criando-a se não existir.
  /// O resultado é cacheado em memória durante a sessão.
  Future<String> ensureFolder() async {
    if (_folderId != null) return _folderId!;

    final api = await _api();

    final query = "mimeType = 'application/vnd.google-apps.folder' "
        "and name = '${_escapeQuery(folderName)}' "
        "and trashed = false";

    final result = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      _folderId = result.files!.first.id;
      return _folderId!;
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await api.files.create(folder, $fields: 'id');
    _folderId = created.id;
    return _folderId!;
  }

  /// Verifica se já existe um arquivo com esse nome dentro da pasta.
  Future<bool> fileExists(String fileName, String folderId) async {
    final api = await _api();

    final query = "name = '${_escapeQuery(fileName)}' "
        "and '$folderId' in parents "
        "and trashed = false";

    final result = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
      pageSize: 1,
    );

    return result.files != null && result.files!.isNotEmpty;
  }

  String _escapeQuery(String value) => value.replaceAll("'", "\\'");

  /// Faz upload multipart do arquivo local para a pasta informada.
  /// Retorna o ID do arquivo criado no Drive.
  Future<String> uploadFile({
    required File localFile,
    required String fileName,
    required String folderId,
    required String mimeType,
  }) async {
    final api = await _api();

    final driveFile = drive.File()
      ..name = fileName
      ..parents = [folderId];

    final media = drive.Media(localFile.openRead(), await localFile.length(),
        contentType: mimeType);

    final uploaded = await api.files.create(
      driveFile,
      uploadMedia: media,
      $fields: 'id',
    );

    if (uploaded.id == null) {
      throw Exception('Upload retornou sem ID de arquivo.');
    }
    return uploaded.id!;
  }
}
