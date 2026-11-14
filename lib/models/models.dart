import 'package:changing/theme/app_theme.dart';

/// 记录项目（Project）—— 一个「变化主体」的容器
/// 对应 PRD 术语定义：记录项目
class Project {
  final String id;
  final String name;
  final ProjectType type;
  final RecordFrequency frequency;

  /// 连续记录周数（断更后重置）
  final int streak;

  /// 提醒文案（如「每周五」「每月 1 日」，null 表示不提醒）
  final String? remind;

  /// 记录点数量
  final int count;

  /// 本月是否未记录（驱动首页「拉回」提示）
  final bool monthMissed;

  /// 封面本地路径（null 用类型渐变色占位）
  final String? coverPath;

  /// 是否已归档
  final bool archived;

  const Project({
    required this.id,
    required this.name,
    required this.type,
    required this.frequency,
    this.streak = 0,
    this.remind,
    this.count = 0,
    this.monthMissed = false,
    this.coverPath,
    this.archived = false,
  });

  Project copyWith({
    String? name,
    ProjectType? type,
    RecordFrequency? frequency,
    int? streak,
    String? remind,
    int? count,
    bool? monthMissed,
    String? coverPath,
    bool? archived,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      streak: streak ?? this.streak,
      remind: remind ?? this.remind,
      count: count ?? this.count,
      monthMissed: monthMissed ?? this.monthMissed,
      coverPath: coverPath ?? this.coverPath,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type.label,
        'frequency': frequency.label,
        'streak': streak,
        'remind': remind,
        'count': count,
        'monthMissed': monthMissed ? 1 : 0,
        'coverPath': coverPath,
        'archived': archived ? 1 : 0,
      };

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        type: ProjectTypeX.fromLabel(m['type'] as String? ?? ''),
        frequency: RecordFrequencyX.fromLabel(m['frequency'] as String? ?? ''),
        streak: (m['streak'] as int?) ?? 0,
        remind: m['remind'] as String?,
        count: (m['count'] as int?) ?? 0,
        monthMissed: (m['monthMissed'] as int? ?? 0) == 1,
        coverPath: m['coverPath'] as String?,
        archived: (m['archived'] as int? ?? 0) == 1,
      );
}

/// 记录点（Check-in）—— 项目下的一次拍照记录
/// 对应 PRD 术语定义：记录点
class CheckIn {
  final String id;
  final String projectId;

  /// 记录时间（ISO 8601）
  final DateTime date;

  /// 照片本地路径
  final String photoPath;

  /// 可选备注
  final String? note;

  /// 地理位置（纬度，可选）
  final double? latitude;

  /// 地理位置（经度，可选）
  final double? longitude;

  const CheckIn({
    required this.id,
    required this.projectId,
    required this.date,
    required this.photoPath,
    this.note,
    this.latitude,
    this.longitude,
  });

  /// 是否有地理位置信息
  bool get hasLocation => latitude != null && longitude != null;

  /// 用于时间轴标签的「YYYY-MM」格式
  String get monthLabel {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'projectId': projectId,
        'date': date.toIso8601String(),
        'photoPath': photoPath,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory CheckIn.fromMap(Map<String, dynamic> m) => CheckIn(
        id: m['id'] as String,
        projectId: m['projectId'] as String,
        date: DateTime.parse(m['date'] as String),
        photoPath: m['photoPath'] as String,
        note: m['note'] as String?,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
      );
}
