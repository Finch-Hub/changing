import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// 导出媒体公共工具：保存到系统相册 + 调起系统分享。
///
/// G3 / C4 / L4：导出产物不能只留在应用私有目录，
/// 用户要在系统相册里找得到、能一键分享出去。
class MediaExportService {
  MediaExportService._();
  static final MediaExportService instance = MediaExportService._();

  /// 保存图片到系统相册。
  /// 返回是否成功（无权限时静默失败，调用方给出提示即可）。
  Future<bool> saveImageToGallery(String path) async {
    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }
      await Gal.putImage(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存视频到系统相册。
  Future<bool> saveVideoToGallery(String path) async {
    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }
      await Gal.putVideo(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 调起系统分享面板分享文件（图片 / 视频）。
  Future<void> shareFile(String path, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: text),
    );
  }
}
