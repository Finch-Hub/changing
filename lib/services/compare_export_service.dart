import 'dart:io';
import 'dart:typed_data';

import 'package:changing/models/models.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 对比图导出服务
/// 对应 PRD FR-03：对比结果可导出为图片并保存/分享（含日期标注）。
class CompareExportService {
  CompareExportService._();
  static final CompareExportService instance = CompareExportService._();

  /// 生成并排对比图（含日期标注）
  Future<String> exportSideBySide(
    CheckIn left,
    CheckIn right,
  ) async {
    final lBytes = await File(left.photoPath).readAsBytes();
    final rBytes = await File(right.photoPath).readAsBytes();

    final lImg = img.decodeImage(lBytes);
    final rImg = img.decodeImage(rBytes);
    if (lImg == null || rImg == null) {
      throw const FormatException('无法解码照片');
    }

    // 统一高度，等比缩放
    final targetH = lImg.height < rImg.height ? lImg.height : rImg.height;
    final lResized = img.copyResize(lImg,
        width: (lImg.width * targetH / lImg.height).round(), height: targetH);
    final rResized = img.copyResize(rImg,
        width: (rImg.width * targetH / rImg.height).round(), height: targetH);

    final gap = 8;
    final labelH = 48;
    final width = lResized.width + rResized.width + gap;
    final height = targetH + labelH;

    final canvas = img.Image(width: width, height: height);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

    img.compositeImage(canvas, lResized, dstX: 0, dstY: 0);
    img.compositeImage(canvas, rResized, dstX: lResized.width + gap, dstY: 0);

    // 日期标注
    final lLabel = img.drawString(
      canvas,
      left.monthLabel,
      font: img.arial24,
      x: 8,
      y: targetH + 12,
      color: img.ColorRgb8(255, 255, 255),
    );
    final rLabel = img.drawString(
      lLabel,
      right.monthLabel,
      font: img.arial24,
      x: lResized.width + gap + 8,
      y: targetH + 12,
      color: img.ColorRgb8(255, 255, 255),
    );

    final base = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(base.path, 'exports'));
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final outPath = p.join(
      outDir.path,
      'compare_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(outPath).writeAsBytes(Uint8List.fromList(img.encodeJpg(rLabel)));
    return outPath;
  }
}
