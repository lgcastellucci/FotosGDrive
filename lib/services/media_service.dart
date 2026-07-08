import 'package:flutter/services.dart' show rootBundle;
import 'package:photo_manager/photo_manager.dart';

import '../models/photo_item.dart';

/// Asset embutido no app, copiado pro álbum na primeira vez.
const String _kControlImageAsset = 'assets/control_image.jpg';

/// Dimensões exatas da imagem de controle (ver assets/control_image.jpg
/// / gen_mockups). Usadas para IDENTIFICAR a imagem de controle já
/// salva no álbum — o Android não respeita de forma confiável o nome
/// de arquivo pedido no saveImage (observado: ele salva com um nome
/// numérico qualquer, tipo "1783358322415.jpg"), então comparar por
/// nome não funciona. Nenhuma foto real do álbum escolhido deve ter
/// exatamente esse tamanho quadrado, então serve como identificador
/// seguro e não depende do nome do arquivo.
const int kControlImageWidth = 640;
const int kControlImageHeight = 640;

bool _looksLikeControlImage(AssetEntity asset) {
  return asset.width == kControlImageWidth &&
      asset.height == kControlImageHeight;
}

class MediaService {
  /// Nome do álbum escolhido pelo usuário no primeiro acesso — é nele
  /// que o app procura as fotos a enviar.
  final String albumName;

  MediaService({required this.albumName});

  /// Solicita permissão de acesso a fotos. Retorna true se concedida
  /// (total ou limitada).
  Future<bool> requestPermission() async {
    final result = await PhotoManager.requestPermissionExtend();
    return result.isAuth || result.hasAccess;
  }

  Future<AssetPathEntity?> _findAlbum() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
    );
    for (final album in albums) {
      if (album.name.toLowerCase() == albumName.toLowerCase()) {
        return album;
      }
    }
    return null;
  }

  /// Garante que exista EXATAMENTE UMA imagem de controle no álbum
  /// escolhido pelo usuário, limpando duplicatas se sobrou alguma de
  /// versões anteriores (bug já corrigido: a identificação por nome de
  /// arquivo não funcionava e criava uma nova a cada execução).
  ///
  /// Álbuns sem nenhum arquivo somem da galeria em alguns launchers
  /// (observado na Samsung) — como o app sempre esvazia o álbum
  /// deletando as fotos enviadas, o álbum em si desaparecia. Essa
  /// imagem fica lá permanentemente (nunca é enviada nem excluída)
  /// só pra manter o álbum visível.
  ///
  /// Não crítico: se falhar por qualquer motivo, o app continua
  /// funcionando normalmente, só sem essa proteção.
  Future<void> ensureControlPhoto() async {
    try {
      final album = await _findAlbum();
      final existing = <AssetEntity>[];

      if (album != null) {
        final count = await album.assetCountAsync;
        if (count > 0) {
          final assets = await album.getAssetListRange(start: 0, end: count);
          existing.addAll(assets.where(_looksLikeControlImage));
        }
      }

      if (existing.isNotEmpty) {
        // Já existe pelo menos uma — limpa duplicatas extras (podem
        // ter sobrado de execuções antigas, antes dessa correção).
        if (existing.length > 1) {
          final extraIds = existing.skip(1).map((a) => a.id).toList();
          await PhotoManager.editor.deleteWithIds(extraIds);
        }
        return;
      }

      final bytes = await rootBundle.load(_kControlImageAsset);
      await PhotoManager.editor.saveImage(
        bytes.buffer.asUint8List(),
        filename: 'fotosgdrive_controle.jpg',
        relativePath: 'Pictures/$albumName',
      );
    } catch (_) {
      // Não crítico — o app segue funcionando sem a proteção do álbum.
    }
  }

  /// Procura o álbum escolhido pelo usuário e retorna as fotos nele, EXCLUINDO a(s)
  /// imagem(ns) de controle (identificadas pelas dimensões fixas
  /// 640x640) — essas nunca aparecem pra envio nem exclusão.
  /// Retorna lista vazia se o álbum não existir no dispositivo.
  Future<List<PhotoItem>> listPhotosInAlbum() async {
    final targetAlbum = await _findAlbum();
    if (targetAlbum == null) return [];

    final count = await targetAlbum.assetCountAsync;
    if (count == 0) return [];

    final assets = await targetAlbum.getAssetListRange(start: 0, end: count);

    final items = <PhotoItem>[];
    for (final asset in assets) {
      if (_looksLikeControlImage(asset)) continue; // nunca incluir

      final title = await asset.titleAsync;
      items.add(PhotoItem(
        asset: asset,
        name: title.isNotEmpty ? title : '${asset.id}.jpg',
      ));
    }
    return items;
  }

  /// Deleta as fotos indicadas do dispositivo (dispara o dialog de
  /// confirmação do sistema no Android 11+/14).
  /// Retorna a lista de IDs que foram efetivamente deletados.
  Future<List<String>> deletePhotos(List<PhotoItem> items) async {
    final ids = items.map((e) => e.asset.id).toList();
    final deletedIds = await PhotoManager.editor.deleteWithIds(ids);
    return deletedIds;
  }
}
