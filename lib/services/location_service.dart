import 'dart:io';

import 'package:exif/exif.dart';

/// 照片位置服务：从照片 EXIF 读取 GPS 地理位置。
/// 不依赖定位权限，相机照片自带 GPS 信息时可直接读取；
/// 无 GPS 信息（如导入的老照片、室内拍照）返回 null，静默降级。
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// 从照片文件读取 GPS 经纬度。
  /// 无 GPS 信息 / 读取失败返回 null。
  Future<({double latitude, double longitude})?> readFromExif(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) return null;

      final latRef = data['GPS GPSLatitudeRef']?.toString();
      final latVal = _gpsToFloat(data['GPS GPSLatitude']?.values);
      final lngRef = data['GPS GPSLongitudeRef']?.toString();
      final lngVal = _gpsToFloat(data['GPS GPSLongitude']?.values);

      if (latRef == null || latVal == null || lngRef == null || lngVal == null) {
        return null;
      }

      var latitude = latVal;
      var longitude = lngVal;
      if (latRef == 'S') latitude = -latitude;
      if (lngRef == 'W') longitude = -longitude;

      return (latitude: latitude, longitude: longitude);
    } catch (_) {
      return null;
    }
  }

  /// 把 EXIF 的 GPS 度分秒比值数组转为十进制浮点数。
  double? _gpsToFloat(IfdValues? values) {
    if (values == null || values is! IfdRatios) return null;
    double sum = 0.0;
    double unit = 1.0;
    for (final v in values.ratios) {
      sum += v.toDouble() * unit;
      unit /= 60.0;
    }
    return sum;
  }
}
