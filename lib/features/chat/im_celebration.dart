import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/dunes_theme.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum ImEggEffectKind {
  birthday,
  nationalDay,
  redEnvelope,
  fireworks,
  moonFestival,
  snow,
  gratitude,
  graduation,
  welcome,
  recovery,
  weekend,
  custom,
}

class ImEggEffect {
  const ImEggEffect({
    required this.kind,
    required this.phrase,
    this.customParticles,
    this.customWashColor,
    this.customDurationMs,
    this.customParticleCount,
    this.customMotion,
  });

  final ImEggEffectKind kind;
  final String phrase;
  final List<String>? customParticles;
  final Color? customWashColor;
  final int? customDurationMs;
  final int? customParticleCount;
  final String? customMotion;

  bool get isBirthday => kind == ImEggEffectKind.birthday;

  Duration get duration => Duration(
    milliseconds:
        customDurationMs ??
        (isBirthday || kind == ImEggEffectKind.nationalDay ? 4800 : 3800),
  );

  List<String> get particles =>
      customParticles ??
      switch (kind) {
        ImEggEffectKind.birthday => const ['🎂'],
        ImEggEffectKind.nationalDay => const ['🇨🇳'],
        ImEggEffectKind.redEnvelope => const ['🧧'],
        ImEggEffectKind.fireworks => const ['🎆'],
        ImEggEffectKind.moonFestival => const ['🌕', '🐇', '🥮'],
        ImEggEffectKind.snow => const ['❄️'],
        ImEggEffectKind.gratitude => const ['💜'],
        ImEggEffectKind.graduation => const ['🎓'],
        ImEggEffectKind.welcome => const ['👋'],
        ImEggEffectKind.recovery => const ['🌱'],
        ImEggEffectKind.weekend => const ['🌈'],
        ImEggEffectKind.custom => const ['✨'],
      };

  int get particleCount => customParticleCount ?? (isBirthday ? 56 : 38);

  Color get washColor =>
      customWashColor ??
      switch (kind) {
        ImEggEffectKind.birthday => const Color(0x14F6A9CB),
        ImEggEffectKind.nationalDay => const Color(0x20D92936),
        ImEggEffectKind.redEnvelope => const Color(0x18C92735),
        ImEggEffectKind.fireworks ||
        ImEggEffectKind.graduation => const Color(0x162A175E),
        ImEggEffectKind.moonFestival => const Color(0x166C55A8),
        ImEggEffectKind.snow => const Color(0x184A8EC7),
        ImEggEffectKind.gratitude ||
        ImEggEffectKind.welcome => const Color(0x167E5CE0),
        ImEggEffectKind.recovery ||
        ImEggEffectKind.weekend => const Color(0x164CA681),
        ImEggEffectKind.custom => const Color(0x167E5CE0),
      };
}

ImEggEffect? matchImEggEffect(String text) {
  final value = text.trim();
  final settings = ImEggSettings.instance;
  if (value.isEmpty || !settings.enabled || !settings.imEffectsEnabled) {
    return null;
  }
  for (final rule in settings.rules) {
    if (rule.enabled && rule.phrase.isNotEmpty && value.contains(rule.phrase)) {
      return rule.effect;
    }
  }
  return null;
}

class ImEggRule {
  const ImEggRule({
    required this.phrase,
    required this.effect,
    this.enabled = true,
  });

  final String phrase;
  final ImEggEffect effect;
  final bool enabled;
}

class ImEggSettings {
  ImEggSettings._();

  static final ImEggSettings instance = ImEggSettings._();
  static const _cacheKey = 'dunes_app_easter_egg_config_v1';

  static const _defaultConfig = <String, dynamic>{
    'enabled': true,
    'version': 4,
    'imEffects': <String, dynamic>{
      'enabled': true,
      'replayLatestOnOpen': true,
      'respectReducedMotion': true,
      'maxPer10Minutes': 3,
      'rules': <Map<String, dynamic>>[
        {'phrase': '生日快乐', 'effect': 'birthdayCakeRain', 'enabled': true},
        {'phrase': '国庆快乐', 'effect': 'nationalDayFlags', 'enabled': true},
        {'phrase': '恭喜发财', 'effect': 'redEnvelopeRain', 'enabled': true},
        {'phrase': '红包拿来', 'effect': 'redEnvelopeRain', 'enabled': true},
        {'phrase': '新年快乐', 'effect': 'fireworks', 'enabled': true},
        {'phrase': '恭喜毕业', 'effect': 'confetti', 'enabled': true},
        {'phrase': '中秋快乐', 'effect': 'moonRabbit', 'enabled': true},
        {'phrase': '圣诞快乐', 'effect': 'snowfall', 'enabled': true},
        {'phrase': '谢谢你', 'effect': 'warmGlow', 'enabled': true},
        {'phrase': '欢迎加入', 'effect': 'welcomeSparkle', 'enabled': true},
        {'phrase': '早日康复', 'effect': 'springBloom', 'enabled': true},
        {'phrase': '周末愉快', 'effect': 'rainbow', 'enabled': true},
      ],
    },
    'scenes': <String, dynamic>{
      'performanceGuard': <String, dynamic>{
        'enabled': true,
        'limitParticles': true,
      },
      'taskCompletion': <String, dynamic>{'enabled': false},
      'firstLogin': <String, dynamic>{
        'enabled': false,
        'workdaysOnly': true,
        'before': '09:00',
      },
    },
  };

  Map<String, dynamic> _config = _defaultConfig;
  Future<void>? _loadFuture;
  DateTime? _lastLoadedAt;
  bool _loadInProgress = false;

  bool get enabled => _config['enabled'] != false;
  bool get imEffectsEnabled => _map(_config['imEffects'])['enabled'] != false;
  bool get senderEnabled =>
      (_map(_config['imEffects'])['recipients'] is! List) ||
      (_map(_config['imEffects'])['recipients'] as List).contains('sender');
  bool get activeReceiverEnabled =>
      (_map(_config['imEffects'])['recipients'] is! List) ||
      (_map(_config['imEffects'])['recipients'] as List).contains(
        'activeReceiver',
      );
  bool get replayLatestOnOpen =>
      _map(_config['imEffects'])['replayLatestOnOpen'] != false;
  bool get taskCompletionEnabled =>
      enabled &&
      _map(_map(_config['scenes'])['taskCompletion'])['enabled'] == true;
  bool get seasonalMascotEnabled => _map(_config['mascot'])['enabled'] != false;
  bool get manualThemeOverrideEnabled =>
      _map(_config['theme'])['manualOverride'] != false;
  String get seasonalDecoration {
    if (!seasonalMascotEnabled) return '';
    final now = DateTime.now();
    final key = switch (now.month) {
      3 || 4 || 5 => 'spring',
      6 || 7 || 8 => 'summer',
      9 || 10 || 11 => 'autumn',
      _ => 'winter',
    };
    final decorations = _map(_map(_config['mascot'])['decorations']);
    return (decorations[key] ?? '').toString();
  }

  bool get isNightTheme {
    final theme = _map(_config['theme']);
    if (theme['enabled'] == false) return false;
    final prefsOverride = manualThemeOverrideEnabled
        ? AppEggThemeController.instance.manualOverride.value
        : 'auto';
    if (prefsOverride == 'day') return false;
    if (prefsOverride == 'night') return true;
    if (theme['followSystem'] == true) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    final dayStart = _parseHourMinute(theme['dayStart']) ?? 7 * 60;
    final nightStart = _parseHourMinute(theme['nightStart']) ?? 19 * 60;
    final minute = DateTime.now().hour * 60 + DateTime.now().minute;
    return dayStart < nightStart
        ? minute < dayStart || minute >= nightStart
        : minute >= nightStart && minute < dayStart;
  }

  Map<String, String>? holidayFor(DateTime date) {
    final holidays = _map(_config['holidays']);
    if (_config['enabled'] == false || holidays['enabled'] == false) {
      return null;
    }
    final defaults = <Map<String, String>>[
      {
        'date': '01-01',
        'name': '元旦',
        'category': 'international',
        'greeting': '新年快乐',
        'message': '愿新的一年平安顺遂，万事皆有回响',
        'icon': '🎆',
      },
      {
        'date': '02-14',
        'name': '情人节',
        'category': 'international',
        'greeting': '情人节快乐',
        'message': '愿爱与温柔常伴左右',
        'icon': '💝',
      },
      {
        'date': '04-04',
        'name': '清明安康',
        'category': 'china',
        'greeting': '清明安康',
        'message': '春和景明，记得照顾好自己',
        'icon': '🌿',
      },
      {
        'date': '04-22',
        'name': '世界地球日',
        'category': 'international',
        'greeting': '世界地球日',
        'message': '愿我们一起守护每一份绿色',
        'icon': '🌍',
      },
      {
        'date': '05-01',
        'name': '劳动节快乐',
        'category': 'china',
        'greeting': '劳动节快乐',
        'message': '辛苦了，愿你享受轻松愉快的假期',
        'icon': '🌼',
      },
      {
        'date': '06-01',
        'name': '儿童节快乐',
        'category': 'china',
        'greeting': '儿童节快乐',
        'message': '愿心里一直住着快乐的小孩',
        'icon': '🎈',
      },
      {
        'date': '09-10',
        'name': '教师节快乐',
        'category': 'china',
        'greeting': '教师节快乐',
        'message': '感谢每一份耐心与付出',
        'icon': '💐',
      },
      {
        'date': '10-01',
        'name': '国庆节快乐',
        'category': 'china',
        'greeting': '国庆节快乐',
        'message': '祝祖国繁荣昌盛，愿你和家人假期愉快',
        'icon': '🇨🇳',
      },
      {
        'date': '10-31',
        'name': '万圣节快乐',
        'category': 'international',
        'greeting': '万圣节快乐',
        'message': '愿今天有一点奇妙，也有很多快乐',
        'icon': '🎃',
      },
      {
        'date': '12-24',
        'name': '平安夜快乐',
        'category': 'international',
        'greeting': '平安夜快乐',
        'message': '愿平安喜乐，温暖常在',
        'icon': '🎄',
      },
      {
        'date': '12-25',
        'name': '圣诞快乐',
        'category': 'international',
        'greeting': '圣诞快乐',
        'message': '愿这个冬天有礼物，也有好心情',
        'icon': '🎅',
      },
    ];
    final configured = holidays['dates'];
    final records = configured is List
        ? configured.whereType<Map>().map((item) {
            final configuredDate = (item['date'] ?? '').toString();
            final fallback = defaults.cast<Map<String, String>?>().firstWhere(
              (entry) => entry?['date'] == configuredDate,
              orElse: () => null,
            );
            final startDate = (item['date'] ?? '').toString();
            final name = (item['name'] ?? fallback?['name'] ?? '').toString();
            final configuredIcon = (item['icon'] ?? fallback?['icon'] ?? '✨')
                .toString();
            final icon =
                configuredIcon.trim().toUpperCase() == 'CN' &&
                    (startDate == '10-01' || name.contains('国庆'))
                ? '🇨🇳'
                : configuredIcon;
            return <String, String>{
              'date': startDate,
              'endDate': (item['endDate'] ?? startDate).toString(),
              'name': name,
              'category': (item['category'] ?? fallback?['category'] ?? 'china')
                  .toString(),
              'greeting':
                  (item['greeting'] ??
                          fallback?['greeting'] ??
                          item['name'] ??
                          '')
                      .toString(),
              'message':
                  (item['message'] ?? fallback?['message'] ?? '愿今天有好心情，也有小惊喜')
                      .toString(),
              'icon': icon,
            };
          }).toList()
        : defaults;
    for (final record in records) {
      final startDate = record['date'] ?? '';
      final endDate = record['endDate'] ?? startDate;
      if (!RegExp(r'^\d{2}-\d{2}$').hasMatch(startDate) ||
          !RegExp(r'^\d{2}-\d{2}$').hasMatch(endDate) ||
          record['name']?.isEmpty == true) {
        continue;
      }
      final monthDay =
          '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final isInRange = startDate.compareTo(endDate) <= 0
          ? monthDay.compareTo(startDate) >= 0 &&
                monthDay.compareTo(endDate) <= 0
          : monthDay.compareTo(startDate) >= 0 ||
                monthDay.compareTo(endDate) <= 0;
      if (!isInRange) continue;
      if (record['category'] == 'china' && holidays['chinaEnabled'] == false) {
        continue;
      }
      if (record['category'] == 'international' &&
          holidays['internationalEnabled'] == false) {
        continue;
      }
      final periodStartYear =
          startDate.compareTo(endDate) > 0 && monthDay.compareTo(endDate) <= 0
          ? date.year - 1
          : date.year;
      return <String, String>{
        ...record,
        'periodKey': '$periodStartYear-$startDate-$endDate',
      };
    }
    return null;
  }

  Future<bool> maybeShowHolidayWelcome(BuildContext context, int userId) async {
    final holiday = holidayFor(DateTime.now());
    if (holiday == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final key =
        'dunes_egg_holiday_${userId}_${holiday['periodKey'] ?? holiday['date']}';
    if (prefs.getBool(key) == true || !context.mounted) return false;
    unawaited(prefs.setBool(key, true));
    showAppHolidayWelcome(
      context,
      holiday['greeting'] ?? holiday['name'] ?? '节日快乐',
      message: holiday['message'] ?? '愿今天有好心情，也有小惊喜',
      icon: holiday['icon'] ?? '✨',
    );
    return true;
  }

  Future<void> maybeShowDailyWelcome(BuildContext context, int userId) async {
    final scenes = _map(_config['scenes']);
    final settings = _map(scenes['firstLogin']);
    if (!enabled || settings['enabled'] != true) return;
    final now = DateTime.now();
    if (settings['workdaysOnly'] == true && now.weekday >= DateTime.saturday) {
      return;
    }
    final before = _parseHourMinute(settings['before']) ?? 9 * 60;
    if (now.hour * 60 + now.minute > before) return;
    final prefs = await SharedPreferences.getInstance();
    final dayKey = '${now.year}-${now.month}-${now.day}';
    final key = 'dunes_egg_daily_welcome_${userId}_$dayKey';
    if (prefs.getBool(key) == true || !context.mounted) return;
    unawaited(prefs.setBool(key, true));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8DFFA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A49316D),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.wb_sunny_rounded, color: Color(0xFF8063D8)),
              SizedBox(width: 10),
              Text(
                '早上好，今天也从容一点',
                style: TextStyle(
                  color: Color(0xFF49316D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int? _parseHourMinute(Object? value) {
    final parts = value?.toString().split(':') ?? const <String>[];
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  int get maxPer10Minutes =>
      (_map(_config['imEffects'])['maxPer10Minutes'] as num?)?.toInt() ?? 3;
  int particleCount(int normalCount) {
    final guard = _map(_map(_config['scenes'])['performanceGuard']);
    if (guard['enabled'] == true && guard['limitParticles'] == true) {
      return (normalCount * 0.55).round().clamp(
        math.min(12, normalCount),
        normalCount,
      );
    }
    return normalCount;
  }

  List<ImEggRule> get rules {
    final raw = _map(_config['imEffects'])['rules'];
    if (raw is! List) return const <ImEggRule>[];
    return raw
        .whereType<Map>()
        .map((item) {
          final phrase = (item['phrase'] ?? '').toString().trim();
          final effectKey = (item['effect'] ?? '').toString();
          final kind = _kindFor(effectKey);
          final profile = _map(_map(_config['effects'])[effectKey]);
          final customParticles = _parseParticles(profile['particles']);
          final customColor = _parseColor(profile['washColor']);
          final duration = _boundedInt(profile['durationMs'], 3800, 1000, 8000);
          final count = _boundedInt(profile['particleCount'], 38, 8, 120);
          final motion = _parseMotion(profile['motion']);
          final effect = ImEggEffect(
            kind: kind,
            phrase: phrase,
            customParticles: profile.isEmpty || customParticles.isEmpty
                ? null
                : customParticles,
            customWashColor: profile.isEmpty ? null : customColor,
            customDurationMs: profile.isEmpty ? null : duration,
            customParticleCount: profile.isEmpty ? null : count,
            customMotion: profile.isEmpty ? null : motion,
          );
          return ImEggRule(
            phrase: phrase,
            effect: effect,
            enabled: item['enabled'] != false,
          );
        })
        .where((rule) => rule.phrase.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> ensureLoaded({required String apiBase, required String token}) {
    final lastLoaded = _lastLoadedAt;
    if (_loadInProgress && _loadFuture != null) return _loadFuture!;
    if (_loadFuture != null &&
        (lastLoaded == null ||
            DateTime.now().difference(lastLoaded) <
                const Duration(minutes: 10))) {
      return _loadFuture!;
    }
    _loadInProgress = true;
    _loadFuture = _load(apiBase: apiBase, token: token).whenComplete(() {
      _lastLoadedAt = DateTime.now();
      _loadInProgress = false;
    });
    return _loadFuture!;
  }

  Future<void> _load({required String apiBase, required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        _config = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        AppEggThemeController.instance.refresh();
      } catch (_) {}
    }
    try {
      final response = await http
          .get(
            Uri.parse('$apiBase/app/easter-eggs/config'),
            headers: <String, String>{'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final decoded = jsonDecode(response.body);
      final outer = decoded is Map ? decoded : const <String, dynamic>{};
      final data = outer['data'] is Map ? outer['data'] as Map : outer;
      final raw = data['config'];
      final config = raw is String ? jsonDecode(raw) : raw;
      if (config is! Map) return;
      _config = Map<String, dynamic>.from(config);
      await prefs.setString(_cacheKey, jsonEncode(_config));
      AppEggThemeController.instance.refresh();
    } catch (_) {
      // 使用本机缓存/内置默认值，IM 收发不依赖配置接口可用。
    }
  }

  static Map _map(Object? value) =>
      value is Map ? value : const <String, dynamic>{};

  static ImEggEffectKind _kindFor(String effect) => switch (effect) {
    'birthdayCakeRain' || 'birthdayStar' => ImEggEffectKind.birthday,
    'nationalDayFlags' => ImEggEffectKind.nationalDay,
    'redEnvelopeRain' => ImEggEffectKind.redEnvelope,
    'fireworks' => ImEggEffectKind.fireworks,
    'moonRabbit' => ImEggEffectKind.moonFestival,
    'snowfall' => ImEggEffectKind.snow,
    'warmGlow' => ImEggEffectKind.gratitude,
    'confetti' => ImEggEffectKind.graduation,
    'welcomeSparkle' => ImEggEffectKind.welcome,
    'springBloom' => ImEggEffectKind.recovery,
    'rainbow' => ImEggEffectKind.weekend,
    _ =>
      ImEggSettings._map(ImEggSettings.instance._config['effects'])[effect]
              is Map
          ? ImEggEffectKind.custom
          : ImEggEffectKind.gratitude,
  };

  static List<String> _parseParticles(Object? value) {
    final source = value is List
        ? value
        : value is String
        ? value.split(RegExp(r'\s+'))
        : const [];
    return source
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(12)
        .toList();
  }

  static int _boundedInt(Object? value, int fallback, int min, int max) =>
      ((value as num?)?.toInt() ?? fallback).clamp(min, max);

  static Color? _parseColor(Object? value) {
    final text = value?.toString().trim().replaceFirst('#', '');
    if (text == null ||
        !RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(text)) {
      return null;
    }
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return null;
    return Color(text.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  static String _parseMotion(Object? value) =>
      const {'fall', 'float', 'burst', 'orbit'}.contains(value?.toString())
      ? value.toString()
      : 'fall';
}

OverlayEntry? _activeHolidayOverlay;
Timer? _holidayOverlayTimer;

void showAppHolidayWelcome(
  BuildContext context,
  String greeting, {
  String message = '愿今天有好心情，也有小惊喜',
  String icon = '✨',
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _holidayOverlayTimer?.cancel();
  _activeHolidayOverlay?.remove();
  late final OverlayEntry entry;
  void dismiss() {
    if (!identical(_activeHolidayOverlay, entry)) return;
    entry.remove();
    _activeHolidayOverlay = null;
    _holidayOverlayTimer?.cancel();
    _holidayOverlayTimer = null;
  }

  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: dismiss,
              ),
            ),
            Center(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GestureDetector(
                    onTap: dismiss,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFDFCFBFF),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFFE9E0F4)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3349316D),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(icon, style: const TextStyle(fontSize: 64)),
                          const SizedBox(height: 14),
                          Text(
                            greeting,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF49316D),
                            ),
                          ),
                          if (message.trim().isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Color(0xFF796A8D),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const Text(
                            '轻触任意位置继续',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9A8DAA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  _activeHolidayOverlay = entry;
  overlay.insert(entry);
  _holidayOverlayTimer = Timer(const Duration(seconds: 4), () {
    if (identical(_activeHolidayOverlay, entry)) {
      entry.remove();
      _activeHolidayOverlay = null;
      _holidayOverlayTimer = null;
    }
  });
}

void maybeShowTaskCompletionEffect(BuildContext context, int userId) {
  final settings = ImEggSettings.instance;
  if (!settings.taskCompletionEnabled || !context.mounted) return;
  if (!ImEggPlaybackStore.allowEffect(
    userId: userId,
    conversationId: 2147483647,
    maxPer10Minutes: 1,
  )) {
    // Task celebrations use a shared app bucket rather than a chat ID.
    return;
  }
  showImEggEffect(
    context,
    const ImEggEffect(kind: ImEggEffectKind.graduation, phrase: '任务完成'),
    seed: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Device-local day/night override. Theme is applied by the app root on mobile;
/// web and desktop keep their established appearance.
class AppEggThemeController {
  AppEggThemeController._() {
    Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  static final AppEggThemeController instance = AppEggThemeController._();
  static const _overrideKey = 'dunes_app_easter_egg_theme_override_v1';
  final ValueNotifier<String> manualOverride = ValueNotifier<String>('auto');
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool? _lastNightTheme;
  bool _loaded = false;

  bool get isNight => ImEggSettings.instance.isNightTheme;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      manualOverride.value = prefs.getString(_overrideKey) ?? 'auto';
    } catch (_) {}
    refresh();
  }

  Future<void> setOverride(String value) async {
    final normalized = const {'auto', 'day', 'night'}.contains(value)
        ? value
        : 'auto';
    manualOverride.value = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_overrideKey, normalized);
    } catch (_) {}
    refresh();
  }

  void refresh() {
    final isNight = ImEggSettings.instance.isNightTheme;
    if (_lastNightTheme == isNight) return;
    _lastNightTheme = isNight;
    revision.value++;
  }

  ThemeData theme(ThemeData light) {
    if (!ImEggSettings.instance.isNightTheme) return light;
    return DunesTheme.dark();
  }
}

/// Per-account/per-conversation replay cursor. Only the latest played effect ID
/// is persisted, so opening a busy chat never has to replay an unbounded queue.
class ImEggPlaybackStore {
  ImEggPlaybackStore._();

  static final Map<String, int> _hotIds = <String, int>{};
  static final Map<String, List<DateTime>> _frequency =
      <String, List<DateTime>>{};

  static String _key(int userId, int conversationId) =>
      'im_egg_last_played_${userId}_$conversationId';

  static Future<int> lastPlayedId(int userId, int conversationId) async {
    final key = _key(userId, conversationId);
    final hot = _hotIds[key];
    if (hot != null) return hot;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(key) ?? 0;
    _hotIds[key] = value;
    return value;
  }

  static Future<bool> markPlayed({
    required int userId,
    required int conversationId,
    required int messageId,
  }) async {
    if (userId <= 0 || conversationId <= 0 || messageId <= 0) return false;
    final key = _key(userId, conversationId);
    final previous = await lastPlayedId(userId, conversationId);
    if (messageId <= previous) return false;
    _hotIds[key] = messageId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, messageId);
    return true;
  }

  static bool allowEffect({
    required int userId,
    required int conversationId,
    required int maxPer10Minutes,
  }) {
    if (userId <= 0 || conversationId <= 0) return false;
    final key = _key(userId, conversationId);
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 10));
    final recent = (_frequency[key] ?? <DateTime>[])
      ..removeWhere((value) => value.isBefore(cutoff));
    if (recent.length >= maxPer10Minutes.clamp(1, 20)) {
      _frequency[key] = recent;
      return false;
    }
    recent.add(now);
    _frequency[key] = recent;
    return true;
  }
}

OverlayEntry? _activeEggOverlay;
Timer? _eggOverlayTimer;

void showImEggEffect(BuildContext context, ImEggEffect effect, {int seed = 0}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showImEggEffectOnOverlay(overlay, effect, seed: seed);
}

void showImEggEffectOnOverlay(
  OverlayState overlay,
  ImEggEffect effect, {
  int seed = 0,
}) {
  _eggOverlayTimer?.cancel();
  _activeEggOverlay?.remove();
  _activeEggOverlay = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ImCelebrationRain(
      effect: effect,
      seed: seed,
      onFinished: () {
        if (identical(_activeEggOverlay, entry)) {
          _activeEggOverlay?.remove();
          _activeEggOverlay = null;
          _eggOverlayTimer?.cancel();
          _eggOverlayTimer = null;
        }
      },
    ),
  );
  _activeEggOverlay = entry;
  overlay.insert(entry);
  _eggOverlayTimer = Timer(
    effect.duration + const Duration(milliseconds: 250),
    () {
      if (identical(_activeEggOverlay, entry)) {
        entry.remove();
        _activeEggOverlay = null;
        _eggOverlayTimer = null;
      }
    },
  );
}

class _ImCelebrationRain extends StatefulWidget {
  const _ImCelebrationRain({
    required this.effect,
    required this.seed,
    required this.onFinished,
  });

  final ImEggEffect effect;
  final int seed;
  final VoidCallback onFinished;

  @override
  State<_ImCelebrationRain> createState() => _ImCelebrationRainState();
}

class _ImCelebrationRainState extends State<_ImCelebrationRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_EggParticle> _particles;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.effect.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) widget.onFinished();
          });
    final random = math.Random(
      widget.seed == 0 ? DateTime.now().microsecondsSinceEpoch : widget.seed,
    );
    final particles = widget.effect.particles;
    _particles = List<_EggParticle>.generate(
      ImEggSettings.instance.particleCount(widget.effect.particleCount),
      (index) => _EggParticle(
        x: .025 + random.nextDouble() * .95,
        phase: random.nextDouble() * math.pi * 2,
        drift: 10 + random.nextDouble() * 36,
        size: widget.effect.isBirthday
            ? 20 + random.nextDouble() * 17
            : 18 + random.nextDouble() * 15,
        delay: random.nextDouble() * .2,
        duration: .72 + random.nextDouble() * .28,
        emoji: particles[random.nextInt(particles.length)],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) widget.onFinished();
      });
    } else if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: <Widget>[
                    for (var i = 0; i < _particles.length; i++)
                      _buildParticle(i, width, height),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildParticle(int index, double width, double height) {
    final particle = _particles[index];
    final progress = _reducedMotion
        ? particle.x
        : ((_controller.value - particle.delay) / particle.duration)
              .clamp(0.0, 1.0)
              .toDouble();
    final active = _reducedMotion || _controller.value >= particle.delay;
    final fadeIn = (progress / .1).clamp(0.0, 1.0).toDouble();
    final fadeOut = ((1 - progress) / .16).clamp(0.0, 1.0).toDouble();
    final opacity = active ? math.min(fadeIn, fadeOut).toDouble() : 0.0;
    final motion = widget.effect.customMotion ?? 'fall';
    final centerX = width / 2;
    final centerY = height / 2;
    final (x, y) = switch (motion) {
      'float' => (
        width * particle.x +
            math.sin(progress * math.pi + particle.phase) * particle.drift,
        height + 45 - (height + 90) * progress,
      ),
      'burst' => (
        centerX + math.cos(particle.phase) * width * .62 * progress,
        centerY + math.sin(particle.phase) * height * .62 * progress,
      ),
      'orbit' => (
        centerX +
            math.cos(particle.phase + progress * math.pi * 4) *
                width *
                (.08 + progress * .35),
        centerY +
            math.sin(particle.phase + progress * math.pi * 4) *
                height *
                (.08 + progress * .35),
      ),
      _ => (
        width * particle.x +
            math.sin(progress * math.pi * 2 + particle.phase) * particle.drift,
        -45 + (height + 110) * progress,
      ),
    };
    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(
              _reducedMotion
                  ? 0
                  : math.sin(progress * math.pi * 2 + particle.phase) * .28,
            )
            ..rotateZ(
              _reducedMotion ? 0 : progress * math.pi * 2 + particle.phase,
            ),
          child: Text(
            particle.emoji,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: particle.size,
              height: 1,
              shadows: <Shadow>[
                Shadow(
                  color: const Color(0x50361E51),
                  blurRadius: 5,
                  offset: const Offset(2, 4),
                ),
                Shadow(
                  color: widget.effect.washColor.withValues(alpha: .3),
                  blurRadius: 10,
                  offset: Offset.zero,
                ),
                const Shadow(
                  color: Color(0x66FFFFFF),
                  blurRadius: 1,
                  offset: Offset(-1, -1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EggParticle {
  const _EggParticle({
    required this.x,
    required this.phase,
    required this.drift,
    required this.size,
    required this.delay,
    required this.duration,
    required this.emoji,
  });

  final double x;
  final double phase;
  final double drift;
  final double size;
  final double delay;
  final double duration;
  final String emoji;
}
