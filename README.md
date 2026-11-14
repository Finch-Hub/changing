# 变化记录 App（changing）

跨时间照片变化记录工具：对齐拍照 → 时间轴对比 → 缩时影片。

## 技术栈

| 维度 | 选型 | 说明 |
|------|------|------|
| 框架 | Flutter (Dart) | 一套代码双端，UI 像素级还原暖橙设计稿 |
| 状态管理 | Provider | 轻量，配合 ChangeNotifier |
| 本地存储 | sqflite (SQLite) | 本地优先架构的第一支柱 |
| 相机 | camera + 参考图虚影叠加 | 对齐拍照核心 |
| 图片处理 | image | 封面缩略 / 对比图导出 |
| 缩时影片 | ffmpeg_kit_flutter | 照片合成视频 + 日期字幕 |
| 内购 | in_app_purchase | 订阅会员 |
| 应用锁 | local_auth | 指纹/面容 |

## 目录结构

```
lib/
├─ main.dart                    入口 + 路由
├─ theme/app_theme.dart         暖橙设计 Token（#E8783C）
├─ models/models.dart           Project / CheckIn 数据模型
├─ data/
│  ├─ database.dart             SQLite 存储层
│  └─ file_store.dart           照片文件本地存储
├─ providers/
│  ├─ project_repository.dart   项目仓库（状态管理）
│  └─ app_settings.dart         全局设置（订阅/云备份/应用锁）
├─ services/
│  ├─ lapse_service.dart        缩时影片合成（FFmpeg）
│  └─ compare_export_service.dart 对比图导出
├─ widgets/
│  ├─ common.dart               TabBar / 分段选择器 / 按钮
│  └─ project_card.dart         项目卡片
└─ pages/
   ├─ home_page.dart            首页「记录」+ 新建项目弹层
   ├─ capture_page.dart         对齐拍照（参考图虚影 + 十字线）
   ├─ compare_page.dart         对比视图（滑块/并排/叠加）
   ├─ lapse_page.dart           缩时影片生成
   └─ mine_page.dart            「我的」（订阅/隐私/设置）
```

## 快速开始

需要 Flutter SDK（stable 通道）与 Android SDK / Xcode，安装见 [Flutter 官方指南](https://docs.flutter.dev/get-started/install)。

```bash
# 1. 拉取依赖
flutter pub get

# 2. 在已连接的设备或模拟器上运行
flutter run

# 3. 构建 debug APK（产物：build/app/outputs/flutter-apk/app-debug.apk）
flutter build apk --debug

# 4. 出正式包
flutter build appbundle   # Android（Google Play）
flutter build ipa         # iOS（App Store，需 macOS）
```

> 本应用使用 `sqflite` 等原生插件，需在 Android / iOS 设备或模拟器上运行，不支持 Web。

## 配套产物

- `ci/` — GitHub Actions + Fastlane 自动构建（Android），密钥走 Secrets 环境变量
- `store-listing/` — 双商店上架文案、关键词、ASO 报告、截图规格
- `checklists/` — 无障碍 / 安全 / 商业化三份审核清单

## 设计对齐

遵循《变化记录App-设计规格包》v2.0：
- 主色 `#E8783C`（温暖橙），页面背景 `#FAF7F2`（暖米白）
- 圆角 8/16/24，间距 8 的倍数，字号下限 24
- 自适应：边距 clamp(20, 3.2vw, 32)，安全区动态 insets

## 里程碑（对应 PRD）

- M1：记录项目 + 对齐拍照 + 时间轴对比（已实现骨架）
- M2：提醒 + 缩时影片 + 订阅（已实现骨架）
- M3：灰度验证 W4 留存 ≥ 20%
