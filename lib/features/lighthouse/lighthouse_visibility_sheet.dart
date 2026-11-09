import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/user_avatar_widget.dart';
import '../contacts/contact_member_picker_page.dart';
import '../conversation/conversation_service.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 谁能看到（2026-11-02 v3 · 按原型简化）
//
//   哪里点开就只管哪里：
//   · 行（或资管主体）上的「👥 N」：只管这一行。一人一个开关，名字旁一个词说明状态：
//       规则内 / 单独放行 / 已关闭 / 规则外 / 板块未开（开关置灰）。
//       关掉规则内的人 = 单独关闭；再打开 = 回到规则内。打开规则外的人 = 单独放行（可设期限）。
//   · 汇总卡上的「👥 N」：只管整个板块。开关 = 能进入板块；点人名展开板块细项和期限。
//   · 数据范围（按规则 / 只看放行行 / 全部数据）不在这里，留在管理后台和数据规则一起配。
//   普通人只读；授权管理人（默认许正阳，管理后台可配）可改。开关即时生效。
// ═════════════════════════════════════════════════════════════════════════════

const Color _kVisPrimary = Color(0xFF7B5CD8);
const Color _kVisDeep = Color(0xFF5A458F);
const Color _kVisLine = Color(0xFFE4DCF4);
const Color _kVisCell = Color(0xFFF8F6FC);
const Color _kVisOff = Color(0xFFB04F33);

const _kLedgerModules = {'product', 'supply', 'channel', 'people', 'net_ta', 'analysis'};
const _kFundModules = {'fund_pool', 'business_finance'};

String _moduleLabel(String key) => switch (key) {
  'product' => '产品',
  'supply' => '供给方',
  'channel' => '渠道',
  'people' => '人效',
  'net_ta' => '净TA',
  'analysis' => '分析',
  'fund_pool' => '资金资产',
  'business_finance' => '资管业财对照',
  'bills' => '资管未结往来',
  'fund_plan' => '资管资金计划',
  'fund_flow' => '资管资金流水',
  'fund_transfer' => '资管资金调动',
  'biz' => '业务平台',
  'discount' => '折扣返点',
  _ => key,
};

/// 打开「谁能看到」。坐标全空 = 整个板块（主 Hero）。
/// [manageable] 为 false 时即使是管理人也只读（例如渠道行没有可落地的坐标）。
Future<void> showLighthouseVisibilitySheet(
  BuildContext context, {
  required LighthouseService service,
  required AuthSession session,
  required String title,
  required String module,
  String? product,
  String? productL3,
  String? province,
  String? entity,
  bool drill = false,
  bool manageable = true,
  String? readOnlyNote,
}) {
  final done = showDialog<void>(
    context: context,
    barrierColor: const Color(0xFF241A3D).withAlpha(70),
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: _LhVisibilityDialog(
        service: service,
        session: session,
        title: title,
        module: module,
        product: product,
        productL3: productL3,
        province: province,
        entity: entity,
        drill: drill,
        manageable: manageable,
        readOnlyNote: readOnlyNote,
      ),
    ),
  );
  // 关掉弹窗后这个板块的「👥 N」全部重算。
  return done.whenComplete(() => LhVisibilityCounts.instance.invalidate(module));
}

class _LhVisibilityDialog extends StatefulWidget {
  const _LhVisibilityDialog({
    required this.service,
    required this.session,
    required this.title,
    required this.module,
    required this.product,
    required this.productL3,
    required this.province,
    required this.entity,
    required this.drill,
    required this.manageable,
    required this.readOnlyNote,
  });

  final LighthouseService service;
  final AuthSession session;
  final String title;
  final String module;
  final String? product;
  final String? productL3;
  final String? province;
  final String? entity;
  final bool drill;
  final bool manageable;
  final String? readOnlyNote;

  bool get moduleLevel =>
      (product ?? '').isEmpty &&
      (productL3 ?? '').isEmpty &&
      (province ?? '').isEmpty &&
      (entity ?? '').isEmpty;

  bool get ledger => _kLedgerModules.contains(module);
  bool get fund => _kFundModules.contains(module);

  Map<String, dynamic> get coords => {
    'product': product ?? '',
    'productL3': productL3 ?? '',
    'province': province ?? '',
    'entity': entity ?? '',
  };

  @override
  State<_LhVisibilityDialog> createState() => _LhVisibilityDialogState();
}

// ═════════════════════════════ 「👥 N」人数 ═════════════════════════════

typedef _CountReq = (LighthouseService, String, bool, Map<String, String>);

/// 「👥 N」人数缓存：同一帧里请求的行攒成一批，按 module + drill 一次拉。
/// 弹窗关掉 / 权限改过后按 module 失效重算。
class LhVisibilityCounts extends ChangeNotifier {
  LhVisibilityCounts._();
  static final LhVisibilityCounts instance = LhVisibilityCounts._();

  final Map<String, int> _counts = {};
  final Map<String, _CountReq> _pending = {};
  final Set<String> _inFlight = {};
  final Set<String> _failed = {};
  Timer? _timer;

  static String keyOf(String module, bool drill, Map<String, String> coords) =>
      '$module|${drill ? 1 : 0}|${coords['product'] ?? ''}|${coords['productL3'] ?? ''}|'
      '${coords['province'] ?? ''}|${coords['entity'] ?? ''}';

  int? countOf(String key) => _counts[key];

  void request(LighthouseService service, String module, bool drill, Map<String, String> coords) {
    final key = keyOf(module, drill, coords);
    if (_counts.containsKey(key) ||
        _inFlight.contains(key) ||
        _pending.containsKey(key) ||
        _failed.contains(key)) {
      return;
    }
    _pending[key] = (service, module, drill, coords);
    _timer ??= Timer(const Duration(milliseconds: 60), () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = Map<String, _CountReq>.of(_pending);
    _pending.clear();
    final groups = <String, List<MapEntry<String, _CountReq>>>{};
    for (final e in batch.entries) {
      final g = '${identityHashCode(e.value.$1)}|${e.value.$2}|${e.value.$3}';
      groups.putIfAbsent(g, () => []).add(e);
    }
    for (final entries in groups.values) {
      final first = entries.first.value;
      final keys = entries.map((e) => e.key).toList();
      _inFlight.addAll(keys);
      try {
        final res = await first.$1.fetchVisibilityCounts(
          module: first.$2,
          drill: first.$3,
          rows: [
            for (final e in entries) {'key': e.key, ...e.value.$4},
          ],
        );
        for (final k in keys) {
          final n = res[k];
          if (n != null) {
            _counts[k] = n;
          } else {
            _failed.add(k);
          }
        }
      } catch (_) {
        _failed.addAll(keys);
      } finally {
        _inFlight.removeAll(keys);
      }
      notifyListeners();
    }
  }

  /// 权限改过后：这个板块的人数全部重算。
  void invalidate(String module) {
    bool hit(String k) => k.startsWith('$module|');
    _counts.removeWhere((k, _) => hit(k));
    _failed.removeWhere(hit);
    notifyListeners();
  }
}

/// 「👥 N」入口：账本行 / 汇总卡 / 资管主体卡共用。坐标全空 = 整个板块。
class LhVisibilityChip extends StatelessWidget {
  const LhVisibilityChip({
    super.key,
    required this.service,
    required this.module,
    required this.onTap,
    this.product,
    this.productL3,
    this.province,
    this.entity,
    this.drill = false,
    this.scale = 1.0,
  });

  final LighthouseService service;
  final String module;
  final VoidCallback onTap;
  final String? product;
  final String? productL3;
  final String? province;
  final String? entity;
  final bool drill;
  final double scale;

  Map<String, String> get _coords => {
    if ((product ?? '').isNotEmpty) 'product': product!,
    if ((productL3 ?? '').isNotEmpty) 'productL3': productL3!,
    if ((province ?? '').isNotEmpty) 'province': province!,
    if ((entity ?? '').isNotEmpty) 'entity': entity!,
  };

  @override
  Widget build(BuildContext context) {
    final counts = LhVisibilityCounts.instance;
    final coords = _coords;
    final key = LhVisibilityCounts.keyOf(module, drill, coords);
    return ListenableBuilder(
      listenable: counts,
      builder: (context, _) {
        final n = counts.countOf(key);
        if (n == null) counts.request(service, module, drill, coords);
        final ink = DunesColors.resolve(context, _kVisDeep);
        return Semantics(
          button: true,
          label: n == null ? '谁能看到' : '谁能看到，$n 人',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 2 * scale),
              child: Container(
                height: 22 * scale,
                padding: EdgeInsets.symmetric(horizontal: 7 * scale),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(context, const Color(0xFFF5F2FA), role: DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(11 * scale),
                  border: Border.all(
                    color: DunesColors.resolve(context, const Color(0xFFC9BCF3), role: DunesColorRole.border),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group_outlined, size: 12.5 * scale, color: ink),
                    if (n != null) ...[
                      SizedBox(width: 3 * scale),
                      Text(
                        '$n',
                        style: LhTypography.mono(
                          size: 10.5 * scale,
                          weight: FontWeight.w600,
                          color: ink,
                          height: 1.0,
                          context: context,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════ 弹窗 ═════════════════════════════

class _LhVisibilityDialogState extends State<_LhVisibilityDialog> {
  late final ConversationService _avatarService =
      ConversationService(session: widget.session);
  bool _loading = true;
  String? _error;
  bool _canManage = false;
  String _today = '';
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _candidates = const [];
  final Set<int> _saving = <int>{};
  String _query = '';

  /// 板块弹窗里展开细项的那个人。
  int? _expanded;

  /// 列表顺序在弹窗打开期间固定：第一次加载的顺序为准，开关后原地刷新，
  /// 新加的人放最上面，其它新出现的放最后。
  final List<int> _order = <int>[];
  final Set<int> _pinTop = <int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _avatarService.close();
    super.dispose();
  }

  int _id(Map<String, dynamic> u) => (u['userId'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> _stable(List<Map<String, dynamic>> rows) {
    final ids = rows.map(_id).toList();
    if (_order.isEmpty) {
      _order.addAll(ids);
    } else {
      final known = _order.toSet();
      final top = <int>[];
      for (final id in ids) {
        if (known.contains(id)) continue;
        if (_pinTop.contains(id)) {
          top.add(id);
        } else {
          _order.add(id);
        }
      }
      _order.insertAll(0, top);
    }
    final pos = <int, int>{for (var i = 0; i < _order.length; i++) _order[i]: i};
    final out = List<Map<String, dynamic>>.of(rows);
    out.sort((a, b) => (pos[_id(a)] ?? 1 << 30).compareTo(pos[_id(b)] ?? 1 << 30));
    return out;
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.service.fetchRowVisibility(
        module: widget.module,
        product: widget.product,
        productL3: widget.productL3,
        province: widget.province,
        entity: widget.entity,
        drill: widget.drill,
      );
      List<Map<String, dynamic>> list(Object? raw) => raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final canManage = data['canManage'] == true && widget.manageable;
      setState(() {
        _canManage = canManage;
        _users = list(data['users']);
        _candidates = list(data['candidates']);
        _today = (data['today'] ?? '').toString();
        if (canManage) {
          _candidates = _stable(_candidates);
        } else {
          _users = _stable(_users);
        }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  DateTime get _todayDate => DateTime.tryParse(_today) ?? DateUtils.dateOnly(DateTime.now());

  Future<bool> _submit(
    List<Map<String, dynamic>> items, {
    bool grantEntry = false,
    Set<int> busy = const <int>{},
  }) async {
    if (items.isEmpty) return true;
    setState(() => _saving.addAll(busy));
    try {
      await widget.service.putVisibilityOverrides(items, grantEntry: grantEntry);
      LhVisibilityCounts.instance.invalidate(widget.module);
      await _load(quiet: true);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving.removeAll(busy));
    }
  }

  Map<String, dynamic> _item(
    int userId, {
    String? module,
    bool rowLevel = true,
    required bool enabled,
    String? validTo,
    bool reset = false,
    Map<String, dynamic>? access,
  }) => {
    'userId': userId,
    'module': module ?? widget.module,
    if (rowLevel) ...widget.coords,
    'enabled': enabled,
    'validTo': validTo ?? '',
    'reset': reset,
    'access': ?access,
  };

  Map<String, dynamic>? _map(Object? raw) => raw is Map ? Map<String, dynamic>.from(raw) : null;

  bool get _row => !widget.moduleLevel;
  String get _rowName => (widget.entity ?? '').isNotEmpty ? '这个主体' : '这一行';
  bool _viewAll(Map<String, dynamic> u) => u['source'] == 'view_all' || u['baseSource'] == 'view_all';

  /// 板块那条单独设置（期限 / 细项都挂在它上面）。
  Map<String, dynamic>? _moduleOv(Map<String, dynamic> u) =>
      _map(u['moduleOverride']) ?? (_row ? null : _map(u['override']));

  // ───── 行：开关 ─────
  //   开 → 规则内的人去掉单独关闭；规则外的人单独放行。
  //   关 → 单独放行的人回到规则外；规则内的人单独关闭。

  Future<void> _toggleRow(Map<String, dynamic> user, bool on) async {
    final id = _id(user);
    if (id <= 0 || _saving.contains(id)) return;
    final base = user['baseSource']?.toString() ?? '';
    final ov = _map(user['override']);
    final Map<String, dynamic> item;
    if (ov != null && ((on && base.isNotEmpty) || (!on && base.isEmpty))) {
      item = _item(id, enabled: true, reset: true);
    } else {
      item = _item(id, enabled: on);
    }
    await _submit([item], busy: {id});
  }

  Future<void> _setRowTerm(Map<String, dynamic> user) async {
    final id = _id(user);
    final ov = _map(user['override']);
    final v = await _lhPickTerm(context, (ov?['validTo'] ?? '').toString(), _todayDate);
    if (v == null || !mounted) return;
    await _submit([_item(id, enabled: true, validTo: v)], busy: {id});
  }

  // ───── 板块：开关 / 细项 / 期限 ─────

  Map<String, dynamic> _accessOf(Map<String, dynamic> user, {bool? drill, bool? cash, bool? total, bool? entity}) {
    final a = _map(user['access']) ?? const <String, dynamic>{};
    final items = (a['fundItems'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
    final t = total ?? items.contains('assets_total');
    final e = entity ?? items.contains('assets_entity');
    return {
      if (widget.ledger) 'drill': drill ?? (a['drill'] == true),
      if (widget.ledger) 'cash': cash ?? (a['cash'] != false),
      if (widget.fund) 'fundItems': [if (t) 'assets_total', if (e) 'assets_entity'],
    };
  }

  Future<void> _toggleModule(Map<String, dynamic> user, bool on) async {
    final id = _id(user);
    if (id <= 0 || _saving.contains(id)) return;
    final base = user['baseSource']?.toString() ?? '';
    final ov = _moduleOv(user);
    final Map<String, dynamic> item;
    if (on && base.isNotEmpty && ov != null && ov['enabled'] != true) {
      item = _item(id, rowLevel: false, enabled: true, reset: true);
    } else {
      item = _item(
        id,
        rowLevel: false,
        enabled: on,
        validTo: on ? (ov?['validTo'] ?? '').toString() : null,
        access: on
            ? (ov?['access'] is Map
                  ? _map(ov!['access'])
                  : _accessOf(user, drill: true, cash: true, total: true, entity: true))
            : null,
      );
    }
    if (!on && _expanded == id) _expanded = null;
    await _submit([item], busy: {id});
  }

  Future<void> _setModuleAccess(Map<String, dynamic> user, Map<String, dynamic> access) async {
    final id = _id(user);
    if (id <= 0 || _saving.contains(id)) return;
    final ov = _moduleOv(user);
    await _submit([
      _item(
        id,
        rowLevel: false,
        enabled: true,
        validTo: (ov?['validTo'] ?? '').toString(),
        access: access,
      ),
    ], busy: {id});
  }

  Future<void> _setModuleTerm(Map<String, dynamic> user) async {
    final id = _id(user);
    final ov = _moduleOv(user);
    final v = await _lhPickTerm(context, (ov?['validTo'] ?? '').toString(), _todayDate);
    if (v == null || !mounted) return;
    await _submit([
      _item(id, rowLevel: false, enabled: true, validTo: v, access: _accessOf(user)),
    ], busy: {id});
  }

  // ───── 添加成员（沙丘通讯录）：直接授权，不再弹明细 ─────
  //   行上添加：开这一行 + 开板块；账本另把数据范围设成「只看放行的行」，免得整个板块露出去。
  //   板块上添加：开板块（细项全开），数据范围不动。

  Future<void> _addMembers() async {
    final exclude = <int>{for (final u in _candidates) _id(u)};
    final picked = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => ContactMemberPickerPage(
          session: widget.session,
          title: '添加可见成员',
          excludeIds: exclude,
        ),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    final full = <String, dynamic>{
      if (widget.ledger) 'drill': true,
      if (widget.ledger) 'cash': true,
      if (widget.fund) 'fundItems': ['assets_total', 'assets_entity'],
    };
    final items = <Map<String, dynamic>>[];
    for (final id in picked) {
      if (_row) items.add(_item(id, enabled: true));
      items.add(_item(id, rowLevel: false, enabled: true, access: full));
      if (_row && widget.ledger && (widget.entity ?? '').isEmpty) {
        items.add(_item(id, module: '*', rowLevel: false, enabled: true, access: {'dataScope': 'rows'}));
      }
    }
    _pinTop.addAll(picked);
    await _submit(items, grantEntry: true, busy: picked.toSet());
  }

  // ───── 文案 ─────

  /// 行弹窗名字旁那个词：(文案, 前景色, 底色)。
  (String, Color, Color) _rowStatus(Map<String, dynamic> user) {
    const grey = (Color(0xFF5A5C56), Color(0xFFEEEEF1));
    const green = (Color(0xFF2F6B3A), Color(0xFFE8F1E4));
    const purple = (_kVisDeep, Color(0xFFF0ECF6));
    const red = (Color(0xFFA33A2A), Color(0xFFF8E6E0));
    (String, Color, Color) t(String s, (Color, Color) c) => (s, c.$1, c.$2);
    switch (user['source']?.toString() ?? '') {
      case 'view_all':
        return t('全部数据', green);
      case 'unrestricted':
      case 'rule':
        return t('规则内', green);
      case 'override_on':
        return t('单独放行', purple);
      case 'override_off':
        return t('已关闭', red);
    }
    if (user['noEntry'] == true) return t('板块未开', grey);
    return t('规则外', grey);
  }

  String _moduleSummary(Map<String, dynamic> user) {
    if (user['visible'] != true) return '未开通';
    if (_viewAll(user)) return '全部数据权限';
    final a = _map(user['access']) ?? const <String, dynamic>{};
    final parts = <String>[];
    if (widget.ledger) {
      parts.add(a['drill'] == true ? '可下钻明细' : '仅汇总');
      if (a['cash'] != false) parts.add('可看现金流');
    } else if (widget.fund) {
      final items = (a['fundItems'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
      if (items.contains('assets_total')) parts.add('可看合计');
      if (items.contains('assets_entity')) parts.add('可看主体明细');
      if (parts.isEmpty) parts.add('无细项');
    } else {
      parts.add('已开通');
    }
    final ov = _moduleOv(user);
    if (ov != null && ov['enabled'] == true) {
      final term = _lhTermText((ov['validTo'] ?? '').toString(), _today, _todayDate);
      if (term != '永久') parts.add(term);
    }
    return parts.join(' · ');
  }

  String get _footNote {
    if (_row) {
      return '开关即时生效。「规则内」= 管理后台的数据规则本来就让他看；关掉为单独关闭，再打开恢复规则内。'
          '「板块未开」的人需先在汇总的「👥」里开通板块。';
    }
    return switch (widget.module) {
      'bills' => '开关即时生效。未结往来是全公司数据，只能看部分省份的账号即使打开也看不到。',
      'fund_plan' => '开关即时生效。资金计划是全公司数据，只能看部分省份的账号即使打开也看不到。',
      'fund_flow' => '开关即时生效。资金流水是全公司数据，只能看部分省份的账号即使打开也看不到。',
      'fund_transfer' => '开关即时生效。资金调动是全公司数据，跟资金流水分开授权；只能看部分省份的账号即使打开也看不到。',
      'business_finance' => '开关即时生效。单个主体去主体卡上的「👥」里调整。',
      _ => '开关即时生效。能看哪些行由管理后台的数据规则决定；单独某一行去那一行的「👥」里调整。',
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = _canManage ? _candidates : _users;
    final q = _query.trim();
    final shown = q.isEmpty
        ? rows
        : rows
              .where(
                (u) =>
                    (u['userName']?.toString() ?? '').contains(q) ||
                    (u['department']?.toString() ?? '').contains(q),
              )
              .toList();
    final visibleCount = _canManage
        ? _candidates.where((u) => u['visible'] == true).length
        : _users.length;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 440, maxHeight: _canManage ? 660 : 560),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kVisDeep.withAlpha(30),
              blurRadius: 30,
              spreadRadius: -8,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, visibleCount),
              if (rows.length > 8)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: LhTypography.sans(size: 12.5, context: context),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 16),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32),
                        hintText: '搜姓名或部门',
                        hintStyle: LhTypography.sans(
                          size: 12,
                          color: DunesColors.resolve(context, LhColors.mute2),
                          context: context,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        filled: true,
                        fillColor: DunesColors.resolve(context, _kVisCell),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _error!.isEmpty ? '可见人员暂时加载失败' : _error!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (shown.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(q.isEmpty ? '当前没有人能看到$_rowName' : '没有匹配的人'),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: shown.length,
                    itemBuilder: (context, index) => KeyedSubtree(
                      key: ValueKey<int>(_id(shown[index])),
                      child: _row
                          ? _rowPerson(context, shown[index])
                          : _modulePerson(context, shown[index]),
                    ),
                  ),
                ),
              if (!_loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Text(
                    _canManage ? _footNote : (widget.readOnlyNote ?? '名单由板块权限与数据规则共同决定，调整请联系授权管理人。'),
                    style: LhTypography.sans(
                      size: 10.5,
                      color: DunesColors.resolve(context, LhColors.mute2),
                      height: 1.6,
                      context: context,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int count) {
    final moduleName = _moduleLabel(widget.module);
    final scope = _row
        ? '只管$_rowName，不影响其他行和整个板块'
        : '管整个$moduleName板块：开 = 能进入';
    final countText = _loading
        ? ''
        : (_row ? '$count 人可见' : '$count 人可进入');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DunesColors.resolve(context, _kVisLine), width: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.title} · 谁能看到',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(
                    size: 15,
                    weight: FontWeight.w700,
                    color: DunesColors.resolve(context, LhColors.ink),
                    height: 1.25,
                    context: context,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, size: 18, color: DunesColors.resolve(context, LhColors.mute)),
              ),
            ],
          ),
          if (_canManage)
            Text(
              scope,
              style: LhTypography.sans(
                size: 11,
                color: DunesColors.resolve(context, LhColors.ink2),
                context: context,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                countText,
                style: LhTypography.sans(
                  size: 12,
                  weight: FontWeight.w700,
                  color: DunesColors.resolve(context, _kVisDeep),
                  context: context,
                ),
              ),
              const Spacer(),
              if (_canManage && !_loading)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _addMembers,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DunesColors.resolve(context, const Color(0xFFDCD5F3)), width: 0.8),
                    ),
                    child: Text(
                      '＋ 添加',
                      style: LhTypography.sans(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: DunesColors.resolve(context, _kVisPrimary),
                        context: context,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> user, bool on) {
    final id = _id(user);
    final name = user['userName']?.toString() ?? '';
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: ImUserAvatar(
        initial: name.trim().isNotEmpty ? name.trim().substring(0, 1) : '人',
        seed: id,
        size: 32,
        avatarPreset: user['avatarPreset']?.toString(),
        avatarObjectKey: user['avatarObjectKey']?.toString(),
        avatarUrl: user['avatarUrl']?.toString(),
        avatarService: _avatarService,
        fallbackBackground: DunesColors.resolve(context, _kVisPrimary).withAlpha(20),
        fallbackForeground: DunesColors.resolve(context, _kVisPrimary),
      ),
    );
  }

  Widget _switch(bool value, bool saving, ValueChanged<bool>? onChanged, {double scale = 1}) {
    return SizedBox(
      width: 52 * scale,
      height: 32 * scale,
      child: saving
          ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
          : FittedBox(
              child: Switch.adaptive(value: value, activeTrackColor: _kVisPrimary, onChanged: onChanged),
            ),
    );
  }

  Widget _nameText(BuildContext context, String name, bool on) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: LhTypography.sans(
      size: 13,
      weight: FontWeight.w600,
      color: DunesColors.resolve(context, on ? LhColors.ink : LhColors.mute2),
      context: context,
    ),
  );

  Widget _smallText(BuildContext context, String text, {Color? color}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: LhTypography.sans(
      size: 10.5,
      color: DunesColors.resolve(context, color ?? LhColors.mute),
      context: context,
    ),
  );

  /// 行弹窗的一个人：名字 + 状态词 + 开关；单独放行的人下面可改期限。
  Widget _rowPerson(BuildContext context, Map<String, dynamic> user) {
    final id = _id(user);
    final name = user['userName']?.toString() ?? '未命名用户';
    final on = _canManage ? user['visible'] == true : true;
    final saving = _saving.contains(id);
    final noEntry = user['noEntry'] == true;
    final status = _rowStatus(user);
    final dept = user['department']?.toString() ?? '';
    final ov = _map(user['override']);
    final released = user['source']?.toString() == 'override_on' && ov != null;
    final term = released ? _lhTermText((ov?['validTo'] ?? '').toString(), _today, _todayDate) : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.resolve(context, const Color(0xFFF3F0F8)), width: 0.8)),
      ),
      child: Row(
        children: [
          _avatar(user, on),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(child: _nameText(context, name, on)),
                    const SizedBox(width: 6),
                    _statusChip(context, status.$1, status.$2, status.$3),
                  ],
                ),
                if (dept.isNotEmpty || (term != null && _canManage)) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (dept.isNotEmpty) Flexible(child: _smallText(context, dept)),
                      if (dept.isNotEmpty && term != null && _canManage) const SizedBox(width: 8),
                      if (term != null && _canManage)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: saving ? null : () => unawaited(_setRowTerm(user)),
                          child: _smallText(
                            context,
                            '期限：$term ▾',
                            color: term == '已到期' ? _kVisOff : _kVisDeep,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_canManage)
            _switch(
              on,
              saving,
              noEntry && !on ? null : (v) => unawaited(_toggleRow(user, v)),
            ),
        ],
      ),
    );
  }

  /// 板块弹窗的一个人：名字 + 概况 + 开关；点名字展开细项和期限。
  Widget _modulePerson(BuildContext context, Map<String, dynamic> user) {
    final id = _id(user);
    final name = user['userName']?.toString() ?? '未命名用户';
    final on = _canManage ? user['visible'] == true : true;
    final saving = _saving.contains(id);
    final open = _canManage && on && _expanded == id;
    final viewAll = _viewAll(user);
    final dept = user['department']?.toString() ?? '';
    final summary = _canManage ? _moduleSummary(user) : dept;

    final head = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      child: Row(
        children: [
          _avatar(user, on),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _canManage && on ? () => setState(() => _expanded = open ? null : id) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(child: _nameText(context, name, on)),
                      if (_canManage && on) ...[
                        const SizedBox(width: 2),
                        Icon(
                          open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 16,
                          color: DunesColors.resolve(context, LhColors.mute2),
                        ),
                      ],
                    ],
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _smallText(context, summary),
                  ],
                ],
              ),
            ),
          ),
          if (_canManage) _switch(on, saving, (v) => unawaited(_toggleModule(user, v))),
        ],
      ),
    );

    if (!open) {
      return Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: DunesColors.resolve(context, const Color(0xFFF3F0F8)), width: 0.8)),
        ),
        child: head,
      );
    }

    final a = _map(user['access']) ?? const <String, dynamic>{};
    final items = (a['fundItems'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
    Widget sub(String label, bool value, ValueChanged<bool> onChanged) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: LhTypography.sans(
              size: 12,
              color: DunesColors.resolve(context, viewAll ? LhColors.mute2 : LhColors.ink),
              context: context,
            ),
          ),
        ),
        _switch(value, false, viewAll || saving ? null : onChanged, scale: 0.85),
      ],
    );
    final subs = <Widget>[
      if (widget.ledger) ...[
        sub('可下钻明细', a['drill'] == true, (v) => unawaited(_setModuleAccess(user, _accessOf(user, drill: v)))),
        sub('可看经营性净现金流', a['cash'] != false, (v) => unawaited(_setModuleAccess(user, _accessOf(user, cash: v)))),
      ],
      if (widget.fund) ...[
        sub('可看合计', items.contains('assets_total'), (v) => unawaited(_setModuleAccess(user, _accessOf(user, total: v)))),
        sub('可看主体明细', items.contains('assets_entity'), (v) => unawaited(_setModuleAccess(user, _accessOf(user, entity: v)))),
      ],
    ];
    final ov = _moduleOv(user);
    final term = ov != null && ov['enabled'] == true
        ? _lhTermText((ov['validTo'] ?? '').toString(), _today, _todayDate)
        : '永久';

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.resolve(context, const Color(0xFFF3F0F8)), width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          Container(
            margin: const EdgeInsets.fromLTRB(58, 0, 14, 10),
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
            decoration: BoxDecoration(
              color: DunesColors.resolve(context, const Color(0xFFF7F6FA), role: DunesColorRole.surface),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _smallText(context, '这个板块没有细项，只有整块开关。'),
                  )
                else
                  ...subs,
                if (viewAll)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _smallText(context, '此人有全部数据权限，细项不受限制；可以整块关掉。'),
                  ),
                Container(
                  height: 0.6,
                  color: DunesColors.resolve(context, _kVisLine),
                ),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '期限',
                          style: LhTypography.sans(size: 12, color: DunesColors.resolve(context, LhColors.ink), context: context),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: saving || viewAll ? null : () => unawaited(_setModuleTerm(user)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '$term ▾',
                            style: LhTypography.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: DunesColors.resolve(context, term == '已到期' ? _kVisOff : _kVisDeep),
                              context: context,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _statusChip(BuildContext context, String text, Color fg, Color bg) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(
    color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(
    text,
    style: LhTypography.sans(
      size: 10,
      weight: FontWeight.w600,
      color: DunesColors.resolve(context, fg),
      context: context,
    ),
  ),
);

String _lhTermText(String validTo, String today, DateTime todayDate) {
  if (validTo.isEmpty) return '永久';
  if (today.isNotEmpty && validTo.compareTo(today) < 0) return '已到期';
  final d = DateTime.tryParse(validTo);
  if (d == null) return '至 $validTo';
  return d.year == todayDate.year
      ? '至 ${d.month}.${d.day.toString().padLeft(2, '0')}'
      : '至 ${d.year}.${d.month}.${d.day.toString().padLeft(2, '0')}';
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 选期限：永久 / 1 个月 / 3 个月 / 6 个月 / 1 年 / 自定义。到期当天结束后自动关闭。
/// 返回 '' = 永久，yyyy-MM-dd = 有效至；null = 没选。
Future<String?> _lhPickTerm(BuildContext context, String current, DateTime today) async {
  DateTime plus(int months) => DateTime(today.year, today.month + months, today.day);
  final options = <(String, String)>[
    ('永久有效', ''),
    ('1 个月', _fmtDate(plus(1))),
    ('3 个月', _fmtDate(plus(3))),
    ('6 个月', _fmtDate(plus(6))),
    ('1 年', _fmtDate(plus(12))),
  ];
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: DunesColors.resolve(ctx, Colors.white, role: DunesColorRole.surface),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                '权限期限 · 到期当天结束后自动关闭',
                style: LhTypography.sans(size: 14, weight: FontWeight.w700, context: ctx),
              ),
            ),
            for (final (label, value) in options)
              ListTile(
                dense: true,
                title: Text(label, style: LhTypography.sans(size: 14, context: ctx)),
                subtitle: value.isEmpty ? null : Text('至 $value', style: LhTypography.mono(size: 10.5, context: ctx)),
                trailing: value == current ? const Icon(Icons.check_rounded, size: 18, color: _kVisPrimary) : null,
                onTap: () => Navigator.of(ctx).pop(value),
              ),
            ListTile(
              dense: true,
              title: Text('自定义日期…', style: LhTypography.sans(size: 14, context: ctx)),
              onTap: () => Navigator.of(ctx).pop('custom'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
  if (picked != 'custom') return picked;
  if (!context.mounted) return null;
  final initial = DateTime.tryParse(current) ?? plus(1);
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(today) ? today : initial,
    firstDate: today,
    lastDate: DateTime(today.year + 5, 12, 31),
    helpText: '权限有效至（含当天）',
  );
  return date == null ? null : _fmtDate(date);
}
