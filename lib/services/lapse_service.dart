import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:changing/models/models.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 缩时影片生成服务（照片 -> 视频）
/// 对应 PRD FR-04：一键把项目内所有记录点合成缩时影片。
/// 依赖 FFmpeg（ffmpeg_kit_flutter_new），支持日期字幕与背景音乐。
class LapseService {
  LapseService._();
  static final LapseService instance = LapseService._();

  /// Android 系统字体候选路径（按优先级）。
  /// FFmpeg 的 drawtext 滤镜不会自动搜索系统字体，必须显式指定 fontfile，
  /// 否则报 "Could not load font file" 并以退出码 1 失败。
  static const List<String> _fontCandidates = [
    '/system/fonts/Roboto-Regular.ttf',
    '/system/fonts/DroidSans.ttf',
    '/system/fonts/NotoSansCJK-Regular.ttc',
    '/system/fonts/NotoSans-Regular.ttf',
  ];

  /// 探测一个实际存在的系统字体路径；找不到返回 null。
  static String? _resolveFontPath() {
    for (final f in _fontCandidates) {
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  /// 转义 FFmpeg filter 中 drawtext 的 text 参数。
  /// 单引号包裹时，内部单引号需按 filtergraph 规则转义（'\''）。
  static String _escapeText(String s) => s.replaceAll("'", "'\\''");

  /// 合成缩时影片
  /// [checkIns] 记录点（按时间升序），[withSubtitle] 是否叠加日期字幕，
  /// [bgmStyle] 内置合成 BGM 风格（'轻快' / '舒缓'，免版权），
  /// [bgmPath] 外部背景音乐文件（可选，优先于内置风格）。
  /// [onProgress] 进度回调（0~1，按已处理输入估算）。
  /// 返回导出视频路径。
  Future<String> generateLapse({
    required List<CheckIn> checkIns,
    bool withSubtitle = true,
    String? bgmStyle,
    String? bgmPath,
    void Function(double progress)? onProgress,
  }) async {
    if (checkIns.length < 2) {
      throw const LapseException('记录不足，至少需要 2 张记录点');
    }
    onProgress?.call(0);

    // 无可用字体时降级为不叠字幕，避免 drawtext 直接导致整条命令失败
    final fontPath = _resolveFontPath();
    final drawText = withSubtitle && fontPath != null;

    final base = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(base.path, 'lapses'));
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final outPath = p.join(
      outDir.path,
      'lapse_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    // 单张照片展示时长（秒）
    const durationPerFrame = 0.8;

    // 构建 FFmpeg 输入：为每张照片生成一个输入参数
    final inputs = <String>[];
    final filterParts = <String>[];
    final labels = <String>[];

    // 升序排列
    final sorted = [...checkIns]..sort((a, b) => a.date.compareTo(b.date));

    int inputIndex = 0;
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      final path = c.photoPath;
      final f = File(path);
      if (!await f.exists()) continue;

      // executeWithArguments 的 List 元素会被逐个作为独立 argv 传给 FFmpeg，
      // 选项与值必须分开存放（'-loop 1' 写成单个元素会导致 FFmpeg 无法识别）
      inputs.addAll(['-loop', '1', '-t', '$durationPerFrame', '-i', path]);

      // 标签序号必须与实际已添加的输入序号一致（跳过缺失照片后不致错位）
      final label = '[${inputIndex++}:v]';
      final suffix = 'v${inputIndex - 1}';
      final scale = drawText
          ? '$label scale=1080:1440:force_original_aspect_ratio=decrease,'
              'pad=1080:1440:(ow-iw)/2:(oh-ih)/2,'
              'drawtext=fontfile=\'$fontPath\':'
              'text=\'${_escapeText(c.monthLabel)}\':x=40:y=40:'
              'fontsize=48:fontcolor=white:box=1:boxcolor=black@0.35'
              ':boxborderw=12,format=yuv420p[$suffix];'
          : '$label scale=1080:1440:force_original_aspect_ratio=decrease,'
              'pad=1080:1440:(ow-iw)/2:(oh-ih)/2,format=yuv420p[$suffix];';
      filterParts.add(scale);
      labels.add('[$suffix]');
    }

    if (labels.isEmpty) {
      throw const LapseException('无有效照片可合成');
    }

    // 拼接视频
    final filterComplex = '${filterParts.join()}${labels.join()}'
        'concat=n=${labels.length}:v=1:a=0[v]';

    // 背景音乐（可选）：作为最后一个输入添加，map 用实际序号。
    // 优先外部文件；否则按风格内置合成（免版权）。
    String? bgm =
        (bgmPath != null && File(bgmPath).existsSync()) ? bgmPath : null;
    if (bgm == null && bgmStyle != null) {
      bgm = await _synthesizeBgm(bgmStyle, outDir.path);
    }
    final hasBgm = bgm != null;
    if (hasBgm) {
      inputs.add('-i');
      inputs.add(bgm);
    }
    onProgress?.call(0.3);

    final cmd = [
      ...inputs,
      '-filter_complex',
      filterComplex,
      '-map',
      '[v]',
    ];

    if (hasBgm) {
      // BGM 是第 inputIndex 个输入（照片输入为 0 ~ inputIndex-1）
      cmd.addAll(['-map', '$inputIndex:a', '-c:a', 'aac', '-shortest']);
    }

    cmd.addAll([
      '-r',
      '30',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-movflags',
      '+faststart',
      outPath,
    ]);

    onProgress?.call(0.5);
    final session = await FFmpegKit.executeWithArguments(cmd);
    final ret = await session.getReturnCode();
    onProgress?.call(0.9);

    if (ret != null && ReturnCode.isSuccess(ret)) {
      onProgress?.call(1);
      return outPath;
    } else {
      final value = ret?.getValue();
      // 失败时把 FFmpeg 会话日志落盘，便于真机/模拟器上定位具体报错
      try {
        final logs = await session.getAllLogsAsString();
        final logFile = File(p.join(outDir.path, 'last_error.log'));
        await logFile.writeAsString('exit=$value\ncmd=${cmd.join(" ")}\n\n$logs');
      } catch (_) {}
      throw LapseException('缩时影片生成失败（FFmpeg 退出码 $value）');
    }
  }

  /// L2：内置合成 BGM（纯 Dart 生成 WAV，免版权、无需音频资产）。
  /// '轻快' = C 大调五声音阶琶音（132 BPM），'舒缓' = 慢速正弦长音（60 BPM）。
  /// 返回生成的 wav 路径；失败返回 null（降级为无 BGM）。
  Future<String?> _synthesizeBgm(String style, String dirPath) async {
    try {
      const sampleRate = 22050;
      final upbeat = style == '轻快';
      final seconds = upbeat ? 8.0 : 10.0;
      final n = (sampleRate * seconds).round();
      final samples = Float64List(n);

      if (upbeat) {
        // C 大调五声音阶琶音：C5 E5 G5 A5 G5 E5 …，每音 0.227s（132 BPM 八分）
        const notes = [523.25, 659.25, 783.99, 880.0, 783.99, 659.25];
        final noteLen = (sampleRate * 60 / 132 / 2).round();
        for (var i = 0; i < n; i++) {
          final idx = (i ~/ noteLen) % notes.length;
          final t = (i % noteLen) / sampleRate;
          final env = math.exp(-3.5 * t); // 拨弦式衰减
          samples[i] = 0.5 * env * math.sin(2 * math.pi * notes[idx] * t);
        }
      } else {
        // 舒缓：C4→G4→E4 慢速正弦长音 + 轻微颤音
        const notes = [261.63, 392.0, 329.63];
        final noteLen = n ~/ notes.length;
        for (var i = 0; i < n; i++) {
          final idx = (i ~/ noteLen).clamp(0, notes.length - 1);
          final t = i / sampleRate;
          final local = (i % noteLen) / noteLen;
          final env = math.sin(math.pi * local); // 淡入淡出
          final vib = 1 + 0.004 * math.sin(2 * math.pi * 5 * t);
          samples[i] = 0.4 *
              env *
              math.sin(2 * math.pi * notes[idx] * vib * t);
        }
      }

      // 16-bit PCM WAV
      final bytes = BytesBuilder();
      void w4(String s) => bytes.add(s.codeUnits);
      void wI(int v, int len) {
        for (var i = 0; i < len; i++) {
          bytes.addByte((v >> (8 * i)) & 0xFF);
        }
      }

      final dataSize = n * 2;
      w4('RIFF');
      wI(36 + dataSize, 4);
      w4('WAVE');
      w4('fmt ');
      wI(16, 4); // fmt chunk size
      wI(1, 2); // PCM
      wI(1, 2); // mono
      wI(sampleRate, 4);
      wI(sampleRate * 2, 4); // byte rate
      wI(2, 2); // block align
      wI(16, 2); // bits per sample
      w4('data');
      wI(dataSize, 4);
      for (var i = 0; i < n; i++) {
        final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
        bytes.addByte(v & 0xFF);
        bytes.addByte((v >> 8) & 0xFF);
      }

      final path = p.join(dirPath, 'bgm_$style.wav');
      await File(path).writeAsBytes(bytes.takeBytes());
      return path;
    } catch (_) {
      return null;
    }
  }
}

class LapseException implements Exception {
  final String message;
  const LapseException(this.message);
  @override
  String toString() => message;
}
