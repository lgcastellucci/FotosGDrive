import 'package:photo_manager/photo_manager.dart';

enum UploadStatus { pending, uploading, uploaded, deleted, error }

class PhotoItem {
  final AssetEntity asset;
  final String name;
  UploadStatus status;
  String? driveFileId;
  String? errorMessage;

  PhotoItem({
    required this.asset,
    required this.name,
    this.status = UploadStatus.pending,
    this.driveFileId,
    this.errorMessage,
  });
}
