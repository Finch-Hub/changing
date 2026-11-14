import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置（订阅状态 / 云端备份 / 应用锁）
/// 对应 PRD FR-07 隐私保护、FR-08 商业化。
class AppSettings extends ChangeNotifier {
  static const _kPremium = 'premium';
  static const _kCloudBackup = 'cloudBackup';
  static const _kAppLock = 'appLock';
  static const _kLastBackup = 'lastBackupAt';

  bool _premium = false;
  bool _cloudBackup = false;
  bool _appLock = false;

  /// M3：上次备份时间（null = 尚未备份），展示在云端备份副文案
  DateTime? _lastBackupAt;

  bool get premium => _premium;
  bool get cloudBackup => _cloudBackup;
  bool get appLock => _appLock;
  DateTime? get lastBackupAt => _lastBackupAt;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _premium = sp.getBool(_kPremium) ?? false;
    // 云端备份默认关闭（本地优先 + 告知同意）
    _cloudBackup = sp.getBool(_kCloudBackup) ?? false;
    _appLock = sp.getBool(_kAppLock) ?? false;
    final ts = sp.getInt(_kLastBackup);
    _lastBackupAt =
        ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
    notifyListeners();
  }

  Future<void> setPremium(bool v) async {
    _premium = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPremium, v);
  }

  Future<void> setCloudBackup(bool v) async {
    _cloudBackup = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kCloudBackup, v);
  }

  /// M3：记录一次备份完成时间（云端备份服务接入后调用）
  Future<void> markBackupDone() async {
    _lastBackupAt = DateTime.now();
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastBackup, _lastBackupAt!.millisecondsSinceEpoch);
  }

  Future<void> setAppLock(bool v) async {
    _appLock = v;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAppLock, v);
  }
}
