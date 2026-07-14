import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 全局字号缩放（持久化到本地）。
class AppTextScaleController extends ChangeNotifier {
  AppTextScaleController._();

  static final AppTextScaleController instance = AppTextScaleController._();

  static const _prefsKey = 'dunes_app_text_scale';

  /// 标准 / 较大 / 更大
  static const List<double> presets = <double>[1.0, 1.15, 1.3];
  static const List<String> labels = <String>['标准', '较大', '更大'];

  double _scale = 1.0;
  bool _loaded = false;

  double get scale => _scale;
  bool get loaded => _loaded;

  int get presetIndex {
    final i = presets.indexOf(_scale);
    if (i >= 0) return i;
    // 容错：取最接近的档位
    var best = 0;
    var bestDiff = (presets[0] - _scale).abs();
    for (var j = 1; j < presets.length; j++) {
      final d = (presets[j] - _scale).abs();
      if (d < bestDiff) {
        best = j;
        bestDiff = d;
      }
    }
    return best;
  }

  String get label => labels[presetIndex];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefsKey);
      if (saved != null && saved > 0.5 && saved <= 2.0) {
        _scale = saved;
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> setScale(double value) async {
    final next = value.clamp(0.85, 1.5);
    if ((next - _scale).abs() < 0.001) return;
    _scale = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKey, _scale);
    } catch (_) {}
  }

  Future<void> setPresetIndex(int index) {
    final i = index.clamp(0, presets.length - 1);
    return setScale(presets[i]);
  }
}
