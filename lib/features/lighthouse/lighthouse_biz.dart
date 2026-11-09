import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_main_tab_bar.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';
import 'lighthouse_visibility_sheet.dart';

// ════════════════════════════════════════════════════════════════════════
// 灯塔 › 业务（2026-11-06）
//
//   灯塔顶部「灯塔 | 资管 | 业务」的第三格：业务平台（资管业务库）的只读视图。
//     · 上面「业务脉搏」：左链路盘（四圈存量）+ 右环形心电（今日推送）+ 2×2 读数格，点圈 / 格子切到对应分段；
//       链路口径与 business-go chainScope 一致，流向图、产品列表分段计数、卡片断点三处可以对账；
//     · 下面一张卡：下划线分段 + 筛选 + 卡片列表（同灯塔账本卡的样式）；
//     · 点产品卡：详情页从右滑入（在业务自己的 Navigator 里推，底栏不动），左上返回 / 右滑返回。
//   数据经 lighthouse-go /api/v1/lighthouse/biz/* 转发 business-go，权限是「谁能看到」里的 biz 板块。
//   只显示接口给的字段；绿色只留给涨跌，状态用紫（正常）/ 铜（进行中）/ 珊瑚（失败）/ 灰（停用）。
// ════════════════════════════════════════════════════════════════════════

const _kInk = Color(0xFF1F2421);
const _kInk2 = Color(0xFF5A5C56);
const _kMute = Color(0xFF6E6C66);
const _kEdge = Color(0xFFE7E3EF);
const _kLine = Color(0xFFECE8F3);
const _kPanel = Color(0xFFF7F6FA);
const _kPurple = Color(0xFF7B5CD8);
const _kDeep = Color(0xFF5A458F);
const _kLavender = Color(0xFFF0ECF6);
const _kCopper = Color(0xFF8A5C17);
const _kCopperSoft = Color(0xFFF8EEDD);
const _kCoral = Color(0xFFA3482E);
const _kCoralSoft = Color(0xFFF5E5DC);
const _kGrey = Color(0xFF5A5C56);
const _kGreySoft = Color(0xFFEEEEF1);
const _kHeroNum = Color(0xFF4A3A7A);
const _kChainGrey = Color(0xFF9A98A3);


// ───────────── 业务链路口径（与 business-go chainScope 一一对应） ─────────────
//   以渠道产品为单位逐层嵌套：渠道产品 ⊇ 已连接供给 ⊇ 双端生效 ⊇ 已配结算。
//   四个互斥分段：已贯通 / 未连接供给 / 未双端生效 / 未配结算，合起来正好是全部渠道产品。
const _kChainThrough = 'through';
const _kChainLeakKeys = ['unconnected', 'half', 'unsettled'];

/// 分段 → (名称, 主色, 浅底)。颜色与总览流向图的分支一致。
(String, Color, Color) _chainSeg(String key) => switch (key) {
  _kChainThrough => ('已贯通', _kHeroNum, _kLavender),
  'unconnected' => ('未连接供给', _kChainGrey, _kGreySoft),
  'half' => ('未双端生效', _kCoral, _kCoralSoft),
  'unsettled' => ('未配结算', _kCopper, _kCopperSoft),
  _ => ('全部', _kDeep, _kLavender),
};

/// 卡片断点下标 → 所属分段。
String _chainSegOfBreak(int brk) => switch (brk) {
  0 || 1 => 'unconnected',
  2 => 'half',
  3 => 'unsettled',
  _ => _kChainThrough,
};

/// 占比：<10% 保留一位小数，其余取整；分母为 0 → 「—」。
String _pct(int part, int base) {
  if (base <= 0) return '—';
  final p = part * 100 / base;
  if (p == 0) return '0%';
  if (p < 10) return '${p.toStringAsFixed(1)}%';
  return '${p.round()}%';
}

/// 业务板块在「谁能看到」里的板块键（flow-go lighthouse_module_grant）。
const kLhBizModule = 'biz';

Color _fg(BuildContext context, Color c) => DunesColors.resolve(context, c);
Color _bg(BuildContext context, Color c) =>
    DunesColors.resolve(context, c, role: DunesColorRole.surface);
Color _ln(BuildContext context, Color c) =>
    DunesColors.resolve(context, c, role: DunesColorRole.border);

TextStyle _sans(
  BuildContext context, {
  double size = 12,
  FontWeight weight = FontWeight.w400,
  Color color = _kInk,
  double? height,
}) => LhTypography.sans(context: context, size: size, weight: weight, color: _fg(context, color), height: height);

TextStyle _num(BuildContext context, {double size = 15, Color color = _kInk}) =>
    LhTypography.number(context: context, size: size, color: _fg(context, color)).copyWith(height: 1.1);

BoxDecoration _cardDeco(BuildContext context, {double radius = 18}) => BoxDecoration(
  color: _bg(context, Colors.white),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: _ln(context, _kEdge), width: 0.8),
  boxShadow: [
    BoxShadow(color: const Color(0xFF4A3A7A).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
  ],
);

// ───────────── 取值与格式 ─────────────

String _s(Object? v) => v == null ? '' : v.toString().trim();

int? _i(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? double.tryParse(v.toString().trim())?.toInt();
}

List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const <Map<String, dynamic>>[];

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// 整数千分位；null → 「—」。
String _count(int? n) {
  if (n == null) return '—';
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}

/// 资管金额是元、字符串原样精度：按两位小数展示；取不到 → 「—」。
String _yuan(Object? v) {
  final d = double.tryParse(_s(v));
  if (d == null) return '—';
  return '¥${d.toStringAsFixed(2)}';
}

String _yuanFromFen(Object? v) {
  final d = double.tryParse(_s(v));
  if (d == null) return '—';
  return '¥${(d / 100).toStringAsFixed(2)}';
}

String _subjectDisplay(Object? v) {
  final name = _s(v);
  if (name.isEmpty) return '未关联';
  const prefix = '中国石油天然气股份有限公司';
  return name.startsWith(prefix) ? name.substring(prefix.length) : name;
}

/// 比例：资管存小数或百分数都有，只做去尾零展示，不换算。
String _plain(Object? v) {
  final raw = _s(v);
  final d = double.tryParse(raw);
  if (d == null) return raw.isEmpty ? '—' : raw;
  var t = d.toStringAsFixed(4);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t;
}

String _date(Object? v) {
  final s = _s(v);
  return s.length >= 10 ? s.substring(0, 10) : (s.isEmpty ? '—' : s);
}

/// 「2026-11-06 10:42:13」→ 今天显示 10:42，否则 11-06 10:42。
String _when(Object? v, String today) {
  final s = _s(v);
  if (s.length < 16) return s.isEmpty ? '—' : s;
  final day = s.substring(0, 10);
  final hm = s.substring(11, 16);
  return day == today ? hm : '${s.substring(5, 10)} $hm';
}

enum _Tone { purple, copper, coral, grey }

(Color, Color) _toneColors(_Tone t) => switch (t) {
  _Tone.purple => (_kDeep, _kLavender),
  _Tone.copper => (_kCopper, _kCopperSoft),
  _Tone.coral => (_kCoral, _kCoralSoft),
  _Tone.grey => (_kGrey, _kGreySoft),
};

Widget _tag(BuildContext context, String text, _Tone tone) {
  final (fg, bg) = _toneColors(tone);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    decoration: BoxDecoration(color: _bg(context, bg), borderRadius: BorderRadius.circular(5)),
    child: Text(text, maxLines: 1, style: _sans(context, size: 10.5, weight: FontWeight.w600, color: fg, height: 1.1)),
  );
}

/// 产品配置提交状态，对齐资管 ProductSubmitStatus。
(String, _Tone) _submitStatus(String v) => switch (v.toUpperCase()) {
  'EFFECTIVE' => ('生效', _Tone.purple),
  'PENDING_AUDIT' => ('待审核', _Tone.copper),
  '' => ('—', _Tone.grey),
  _ => ('未配置', _Tone.grey),
};

/// 渠道产品状态是字符串，供应商产品是 1 / 0。
String _productStatus(String side, String v) {
  if (side == 'supplier') return v == '1' ? '启用' : (v == '0' ? '停用' : (v.isEmpty ? '—' : v));
  return switch (v) {
    'active' => '启用',
    'pending' => '待生效',
    'inactive' || 'disabled' => '停用',
    '' => '—',
    _ => v,
  };
}

(String, _Tone) _partnerStatus(String v) => switch (v) {
  '0' => ('正常', _Tone.purple),
  '1' => ('合作到期', _Tone.copper),
  '2' => ('停止合作', _Tone.grey),
  _ => (v.isEmpty ? '—' : v, _Tone.grey),
};

_Tone _proposalTone(String status) => switch (status) {
  '已落地' => _Tone.purple,
  '建档中' => _Tone.copper,
  '入站失败' => _Tone.coral,
  _ => _Tone.grey,
};

String _pushType(String v) => switch (v.toUpperCase()) {
  'PRODUCT_SETTLEMENT' => '产品结算配置',
  'BILL_CONFIG' => '账单配置',
  'PRICE_RULE' => '价格规则',
  '' => '推送',
  _ => v,
};

(String, _Tone) _pushStatus(String v) => switch (v.toUpperCase()) {
  'SUCCESS' => ('成功', _Tone.purple),
  'SKIPPED' => ('跳过', _Tone.grey),
  'FAILED' => ('失败', _Tone.coral),
  _ => (v.isEmpty ? '—' : v, _Tone.grey),
};

(String, _Tone) _returnStatus(String v) => switch (v.toUpperCase()) {
  'SUCCESS' => ('成功', _Tone.purple),
  'PARTIAL' => ('部分成功', _Tone.copper),
  'FAILED' => ('失败', _Tone.coral),
  'REJECTED' => ('已拒绝', _Tone.coral),
  'PROCESSING' => ('处理中', _Tone.copper),
  'PENDING' => ('待处理', _Tone.copper),
  _ => (v.isEmpty ? '—' : v, _Tone.grey),
};

String _errText(Object e) {
  final s = e.toString().replaceFirst('Exception: ', '');
  return s.isEmpty ? '加载失败' : s;
}

// ═════════════════════════════ 入口：业务自己的 Navigator ═════════════════════════════

/// 灯塔内容区里的「业务」：自带 Navigator，详情页在里面推，PC 侧栏和手机底栏都不动。
class LighthouseBizHost extends StatelessWidget {
  const LighthouseBizHost({
    super.key,
    required this.navigatorKey,
    required this.observer,
    required this.service,
    required this.session,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final LighthouseService service;
  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: [observer],
      onGenerateRoute: (settings) {
        final args = _map(settings.arguments);
        if (settings.name == '/partner') {
          // 列表卡片直接带上整行数据（含 productCount），从关系链跳来只带 kind / id，由页面自己取。
          final data = args.containsKey('productCount') ? args : _map(args['data']);
          return CupertinoPageRoute<void>(
            settings: settings,
            builder: (_) => LighthouseBizPartnerPage(
              service: service,
              kind: _s(args['kind']),
              id: _s(args['id']),
              title: _s(args['name']),
              initial: data.isEmpty ? null : data,
              initialTab: _s(args['tab']),
            ),
          );
        }
        if (settings.name == '/settlement') {
          return CupertinoPageRoute<void>(
            settings: settings,
            builder: (_) => LighthouseBizSettlementPage(service: service, side: _s(args['side']), id: _s(args['id']), title: _s(args['name'])),
          );
        }
        if (settings.name == '/subject') {
          return CupertinoPageRoute<void>(
            settings: settings,
            builder: (_) => LighthouseBizSubjectPage(service: service, id: _s(args['id']), title: _s(args['name'])),
          );
        }
        if (settings.name == '/product') {
          // 详情页从右滑入；iOS 风格，可从左缘右滑返回。
          return CupertinoPageRoute<void>(
            settings: settings,
            builder: (_) => LighthouseBizProductPage(
              service: service,
              side: _s(args['side']),
              id: _s(args['id']),
              title: _s(args['name']),
            ),
          );
        }
        return PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => LighthouseBizHubPage(service: service, session: session),
        );
      },
    );
  }
}

// ═════════════════════════════ 业务首页 ═════════════════════════════

enum _BizTab { product, partner, settlement, proposal, link }

class LighthouseBizHubPage extends StatefulWidget {
  const LighthouseBizHubPage({super.key, required this.service, required this.session});

  final LighthouseService service;
  final AuthSession session;

  @override
  State<LighthouseBizHubPage> createState() => _BizHubState();
}

class _BizHubState extends State<LighthouseBizHubPage> {
  static const _pageSize = 20;

  Map<String, dynamic>? _overview;
  String? _overviewError;

  _BizTab _tab = _BizTab.product;
  String _productSide = 'channel';
  String _partnerKind = 'channel';
  String _subjectFilter = '';
  String _settleSide = 'channel';
  String _settleConfigured = '';
  String _chain = '';
  Map<String, dynamic>? _chainCounts;
  bool _showChainDef = false;
  String _proposalKind = '';
  String _linkView = 'push';
  String _platform = '';
  String _keyword = '';
  bool _searching = false;
  final TextEditingController _searchCtl = TextEditingController();

  final List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _listMeta = const {};
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  String? _listError;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    // 先用上一次的总览把表盘画出来，后台再刷新，不让用户对着加载圈。
    _overview = _bizOverviewCache;
    unawaited(_loadOverview());
    unawaited(_loadList());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    try {
      final data = await widget.service.fetchBizOverview();
      if (!mounted) return;
      _bizOverviewCache = data;
      setState(() {
        _overview = data;
        _overviewError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _overviewError = _errText(e));
    }
  }

  Future<Map<String, dynamic>> _fetch(int page) {
    final s = widget.service;
    return switch (_tab) {
      _BizTab.product => s.fetchBizProducts(
        side: _productSide,
        keyword: _keyword,
        syncSource: _platform,
        chain: _productSide == 'channel' ? _chain : '',
        page: page,
        size: _pageSize,
      ),
      _BizTab.partner => s.fetchBizPartners(kind: _partnerKind, keyword: _keyword, subject: _partnerKind != 'promoter' ? _subjectFilter : '', page: page, size: _pageSize),
      _BizTab.settlement => s.fetchBizSettlements(side: _settleSide, configured: _settleConfigured, keyword: _keyword, page: page, size: _pageSize),
      _BizTab.proposal => s.fetchBizProposals(kind: _proposalKind, page: page, size: _pageSize),
      _BizTab.link => s.fetchBizIntegration(view: _linkView),
    };
  }

  Future<void> _loadList() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _listError = null;
      _items.clear();
      _listMeta = const {};
      _page = 1;
    });
    try {
      final data = await _fetch(1);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll(_list(data['items']));
        _listMeta = data;
        _loading = false;
        if (_tab == _BizTab.product && _productSide == 'channel' && data['chain'] is Map) {
          _chainCounts = _map(data['chain']);
        }
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _listError = _errText(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final data = await _fetch(_page + 1);
      if (!mounted || seq != _seq) return;
      setState(() {
        _page += 1;
        _items.addAll(_list(data['items']));
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_errText(e))));
    }
  }

  Future<void> _refresh() async {
    widget.service.clearBizCache();
    await Future.wait([_loadOverview(), _loadList()]);
  }

  void _switchTab(_BizTab t) {
    if (_tab == t) return;
    setState(() {
      _tab = t;
      _keyword = '';
      _searching = false;
      _searchCtl.clear();
    });
    unawaited(_loadList());
  }

  bool get _hasMore {
    if (_tab == _BizTab.link) return false;
    final total = _i(_listMeta['total']) ?? 0;
    return _items.length < total;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = dunesAppBottomNavContentPadding(context, fallback: 16) + 12;
    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        color: _kPurple,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(22, 8, 22, bottom),
          children: [
            _buildOverviewCard(context),
            const SizedBox(height: 12),
            _buildBoardCard(context),
          ],
        ),
      ),
    );
  }

  // ───────────── 业务总览 ─────────────

  Widget _buildOverviewCard(BuildContext context) {
    final o = _overview;
    final synced = _s(o?['generatedAt']);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _cardDeco(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_bg(context, const Color(0xFFEEE9FE)), _bg(context, const Color(0xFFE2F1FD))]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.monitor_heart_outlined, size: 16, color: _fg(context, _kDeep)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('业务脉搏', style: _sans(context, size: 13.5, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('链路存量 · 今日推送节奏', style: _sans(context, size: 10.5, color: _kInk2)),
                  ],
                ),
              ),
              if (synced.length >= 16) ...[
                _LiveDot(color: _fg(context, _kPurple)),
                const SizedBox(width: 5),
                Text(synced.substring(11, 16), style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kInk2))),
                const SizedBox(width: 8),
              ],
              LhVisibilityChip(
                service: widget.service,
                module: kLhBizModule,
                onTap: () => showLighthouseVisibilitySheet(
                  context,
                  service: widget.service,
                  session: widget.session,
                  title: '业务 · 业务平台',
                  module: kLhBizModule,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_overviewError != null && o == null)
            _inlineError(context, _overviewError!, _loadOverview)
          else
            // 数据没到也先出表盘骨架（刻度、空轨道、心电基线、读数格），到了再把圆弧和心电画出来。
            ..._pulseBody(context, o ?? const <String, dynamic>{}, loading: o == null),
        ],
      ),
    );
  }

  /// 链路分层计数 [渠道产品, 已连接供给, 双端生效, 已配结算]；缺任何一层 → null。
  List<int>? _chainValues(Map<String, dynamic> o) {
    final v = [_i(o['chainTotal']), _i(o['chainConnected']), _i(o['chainUsable']), _i(o['chainSettled'])];
    if (v.any((e) => e == null)) return null;
    return v.cast<int>();
  }

  /// 比上一层缩得最多的那一圈（1–3）；用于蜜桃色高亮和底部结论。
  int _chainDropIndex(List<int> v) {
    var drop = 1;
    for (var i = 2; i < 4; i++) {
      if (v[i - 1] - v[i] > v[drop - 1] - v[drop]) drop = i;
    }
    return drop;
  }

  List<Widget> _pulseBody(BuildContext context, Map<String, dynamic> o, {bool loading = false}) {
    final v = _chainValues(o);
    final pulseReady = o['pulse'] is Map;
    final drop = v == null || v[0] == 0 ? -1 : _chainDropIndex(v);
    final pulse = _map(o['pulse']);
    final pushes = [
      for (final e in _list(pulse['pushes'])) (_i(e['minute']) ?? 0, _i(e['count']) ?? 0, _i(e['failed']) ?? 0),
    ];
    final returns = [
      for (final e in _list(pulse['returns'])) (_i(e['minute']) ?? 0, e['abnormal'] == true),
    ];
    final pushTotal = _i(o['todayPushes']) ?? pushes.fold<int>(0, (a, e) => a + e.$2);
    final pushFailed = _i(o['todayPushFailed']) ?? 0;
    final retTotal = _i(o['todayReturnBatches']) ?? returns.length;
    final retAbnormal = _i(o['todayReturnAbnormal']) ?? 0;
    final last = _s(pulse['lastPushAt']);
    return [
      LayoutBuilder(
        builder: (context, box) {
          // 与资管时钟同一把尺：手机约 190，宽屏 240。
          final d = math.min((box.maxWidth - 16) / 2, box.maxWidth >= 720 ? 240.0 : 190.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _dialKicker(context, '链路 · 存量'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: d,
                      height: d,
                      child: loading || (v != null && v[0] > 0)
                          ? _ChainRingDial(values: loading ? null : v, drop: drop, onPick: _openChain)
                          : Center(child: Text(v == null ? '链路计数暂不可用' : '还没有渠道产品', style: _sans(context, size: 10.5, color: _kMute))),
                    ),
                    const SizedBox(height: 8),
                    if (loading || (v != null && v[0] > 0)) _ringLegend(context, loading ? null : v, drop),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _dialKicker(context, '今日 · 24H'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: d,
                      height: d,
                      child: _PulseDial(pushes: pushes, returns: returns, total: pushTotal, onTap: () => _switchTab(_BizTab.link)),
                    ),
                    const SizedBox(height: 8),
                    _todayRow(context, '推送', loading ? '—' : '${_count(pushTotal)} 次', loading ? '' : '失败 ${_count(pushFailed)}', pushFailed > 0),
                    _todayRow(context, '结算回传', loading ? '—' : '${_count(retTotal)} 批', loading ? '' : '异常 ${_count(retAbnormal)}', retAbnormal > 0),
                    _todayRow(context, '最近一次', last.length >= 16 ? last.substring(11, 16) : '—', '', false),
                    if (!loading && !pulseReady)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('心电数据未就绪（服务端未返回分时数据）', style: _sans(context, size: 9.5, color: _kMute)),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 14),
      _vitalBoard(context, o, v, loading: loading),
      const SizedBox(height: 10),
      _flowInsight(context, o, v, drop),
    ];
  }

  Widget _dialKicker(BuildContext context, String text) =>
      Text(text, style: _sans(context, size: 10, color: _kInk2, height: 1.2).copyWith(letterSpacing: 1.2));

  /// 链路盘图例：四层的数量与占渠道产品的比例；流失最多的一层用蜜桃色。点行进入对应产品。
  Widget _ringLegend(BuildContext context, List<int>? values, int drop) {
    final v = values ?? const [0, 0, 0, 0];
    final ready = values != null;
    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          Semantics(
            button: true,
            label: ready ? '${_kRingNames[i]} ${v[i]}，占渠道产品 ${_pct(v[i], v[0])}' : '${_kRingNames[i]} 加载中',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openChain(_kRingKeys[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [for (final c in (i == drop ? _kRingDropGrad : _kRingGrad[i])) _fg(context, c)]),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _kRingNames[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(context, size: 10.5, color: i == drop ? _kCoral : _kInk2),
                      ),
                    ),
                    Text(ready ? _count(v[i]) : '—', style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: _fg(context, _kInk))),
                    SizedBox(
                      width: 34,
                      child: Text(
                        ready ? _pct(v[i], v[0]) : '',
                        textAlign: TextAlign.right,
                        style: LhTypography.mono(context: context, size: 9.5, color: _fg(context, i == drop ? _kCoral : _kMute)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _todayRow(BuildContext context, String label, String value, String extra, bool alert) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        children: [
          Text(label, style: _sans(context, size: 10.5, color: _kInk2)),
          const Spacer(),
          Text(value, style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: _fg(context, _kInk))),
          if (extra.isNotEmpty) ...[
            Text(' · ', style: _sans(context, size: 10.5, color: _kMute)),
            Text(extra, style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: _fg(context, alert ? _kCoral : _kInk))),
          ],
        ],
      ),
    );
  }

  /// 2×2 读数格，样式同资管时钟的指标格：图标 + 名称、数值 + 小环、说明。
  Widget _vitalBoard(BuildContext context, Map<String, dynamic> o, List<int>? v, {bool loading = false}) {
    final sLinked = _i(o['suppliersWithSubject']) ?? 0;
    final sTotal = _i(o['supplierTotal']) ?? 0;
    final cLinked = _i(o['channelsWithSubject']) ?? 0;
    final cTotal = _i(o['channelTotal']) ?? 0;
    final settled = _i(o['channelProductsWithSettlement']) ?? 0;
    final total = v?[0] ?? _i(o['channelProducts']) ?? 0;
    final connected = v?[1] ?? 0;
    final usable = v?[2] ?? 0;
    double? ratio(int a, int b) => b <= 0 ? null : (a / b).clamp(0.0, 1.0).toDouble();
    // 加载中：格子照常画（图标、名称、空环），数值写「—」。
    String val(String text) => loading ? '—' : text;
    String sub(String text) => loading ? '' : text;
    double? prog(double? x) => loading ? null : x;
    final cells = [
      _vitalCell(
        context,
        title: '主体关联',
        icon: Icons.apartment_rounded,
        tone: _kPurple,
        value: val('${_count(sLinked)} / ${_count(sTotal)}'),
        sub: sub('供应商 · ${_pct(sLinked, sTotal)}'),
        progress: prog(ratio(sLinked, sTotal)),
        onTap: () => _openPartners('supplier', 'linked'),
      ),
      _vitalCell(
        context,
        title: '渠道关联',
        icon: Icons.hub_outlined,
        tone: const Color(0xFF4F7FC8),
        value: val('${_count(cLinked)} / ${_count(cTotal)}'),
        sub: sub(cLinked == 0 ? '断点 · 未关联法人主体' : '渠道 · ${_pct(cLinked, cTotal)}'),
        progress: prog(ratio(cLinked, cTotal)),
        alert: !loading && cLinked == 0 && cTotal > 0,
        onTap: () => _openPartners('channel', ''),
      ),
      _vitalCell(
        context,
        title: '结算覆盖',
        icon: Icons.receipt_long_outlined,
        tone: const Color(0xFF4F7FC8),
        value: val(_pct(settled, total)),
        sub: sub('${_count(settled)} 个渠道产品'),
        progress: prog(ratio(settled, total)),
        onTap: _openSettlements,
      ),
      _vitalCell(
        context,
        title: '双端可用率',
        icon: Icons.sync_alt_rounded,
        tone: const Color(0xFF9A5CB8),
        value: val(_pct(usable, connected)),
        sub: sub('${_count(usable)} / ${_count(connected)} 已连接'),
        progress: prog(ratio(usable, connected)),
        onTap: () => _openChain('usable'),
      ),
    ];
    final line = _ln(context, _kLine);
    return Container(
      decoration: BoxDecoration(
        color: _bg(context, Colors.white).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var r = 0; r < 2; r++) ...[
            if (r > 0) Divider(height: 1, thickness: 0.8, color: line),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cells[r * 2]),
                  Container(width: 0.8, color: line),
                  Expanded(child: cells[r * 2 + 1]),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vitalCell(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color tone,
    required String value,
    required String sub,
    required VoidCallback onTap,
    double? progress,
    bool alert = false,
  }) {
    final color = alert ? _kCoral : tone;
    return Semantics(
      button: true,
      label: '$title $value，$sub',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_fg(context, color).withValues(alpha: 0.07), _bg(context, Colors.white).withValues(alpha: 0.02)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(color: _fg(context, color).withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Icon(icon, size: 10, color: _fg(context, color)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10, color: _kInk2))),
                  Icon(Icons.chevron_right_rounded, size: 13, color: _fg(context, _kMute)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LhTypography.mono(context: context, size: 14, weight: FontWeight.w700, color: _fg(context, alert ? _kCoral : const Color(0xFF2B2147))),
                    ),
                  ),
                  SizedBox(
                    width: 21,
                    height: 21,
                    child: CustomPaint(painter: _MiniRingPainter(value: progress, color: _fg(context, color))),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LhTypography.mono(context: context, size: 9.5, color: _fg(context, alert ? _kCoral : _kInk2)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部结论：最大流失 + 主体层断点；点结论进入流失的那段产品，「口径」可展开。
  Widget _flowInsight(BuildContext context, Map<String, dynamic> o, List<int>? v, int drop) {
    final spans = <InlineSpan>[];
    if (v != null && drop > 0) {
      final lost = v[drop - 1] - v[drop];
      spans.addAll([
        // 缺口 = 上一圈里没走到这一圈的产品，用缺口本身的名字（未连接供给 / 未双端生效 / 未配结算），
        // 比例的分母写明是哪一圈，避免读成「已连接供给流失了」。
        const TextSpan(text: '最大缺口：'),
        TextSpan(text: _chainSeg(_kChainLeakKeys[drop - 1]).$1, style: _sans(context, size: 10.5, weight: FontWeight.w600, color: _kCoral)),
        const TextSpan(text: ' '),
        TextSpan(text: _count(lost), style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: _fg(context, _kInk))),
        TextSpan(text: '（占${_kRingNames[drop - 1]} ${_pct(lost, v[drop - 1])}）'),
      ]);
    }
    if ((_i(o['channelsWithSubject']) ?? 0) == 0 && (_i(o['channelTotal']) ?? 0) > 0) {
      spans.addAll([
        TextSpan(text: spans.isEmpty ? '' : ' · '),
        const TextSpan(text: '渠道尚未关联主体'),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: drop > 0 ? () => _openChain(_kChainLeakKeys[drop - 1]) : null,
                child: Text.rich(TextSpan(children: spans), style: _sans(context, size: 10.5, color: _kMute, height: 1.5)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showChainDef = !_showChainDef),
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 12, color: _fg(context, _kMute)),
                    const SizedBox(width: 2),
                    Text('口径', style: _sans(context, size: 10.5, color: _kMute)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_showChainDef) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '链路盘以未删除的渠道产品为单位，四圈逐层嵌套：\n'
              '已连接供给：至少一条货源指向未删除的供应商产品；\n'
              '双端生效：渠道产品审核生效且启用，并且至少一条货源的供应商产品审核生效且启用；\n'
              '已配结算：在双端生效之上，存在未删除的渠道侧结算明细。\n'
              '「结算覆盖」统计全部渠道产品（含未双端生效的），所以大于最内圈；「双端可用率」= 双端生效 ÷ 已连接供给。\n'
              '右盘：今日每 10 分钟一档的推送，跳得越高条数越多，失败向内跳；内圈菱形是结算回传批次。',
              style: _sans(context, size: 10.5, color: _kInk2, height: 1.6),
            ),
          ),
        ],
      ],
    );
  }

  void _resetSearch() {
    _keyword = '';
    _searching = false;
    _searchCtl.clear();
  }

  /// 从流向图进入产品列表：[chain] 为空 = 全部渠道产品。清掉平台筛选，列表数字才和流向图同口径。
  void _openChain(String chain) {
    setState(() {
      _tab = _BizTab.product;
      _productSide = 'channel';
      _chain = chain;
      _platform = '';
      _resetSearch();
    });
    unawaited(_loadList());
  }

  void _openPartners(String kind, String subject) {
    setState(() {
      _tab = _BizTab.partner;
      _partnerKind = kind;
      _subjectFilter = kind == 'supplier' ? subject : '';
      _resetSearch();
    });
    unawaited(_loadList());
  }

  /// 总览「结算覆盖」是已配规则的产品数，进入时默认筛已配置，列表总数与之对得上。
  void _openSettlements() {
    setState(() {
      _tab = _BizTab.settlement;
      _settleSide = 'channel';
      _settleConfigured = 'configured';
      _resetSearch();
    });
    unawaited(_loadList());
  }

  // ───────────── 分段卡 ─────────────

  Widget _buildBoardCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: _cardDeco(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabBar(context),
          const SizedBox(height: 10),
          _filterRow(context),
          if (_tab == _BizTab.product && _productSide == 'channel') ...[
            const SizedBox(height: 10),
            _chainFilter(context),
          ],
          if (_tab == _BizTab.partner && _partnerKind != 'promoter') ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(context, '全部主体', _subjectFilter.isEmpty, () { setState(() => _subjectFilter = ''); unawaited(_loadList()); }),
                const SizedBox(width: 6),
                _chip(context, '已关联主体', _subjectFilter == 'linked', () { setState(() => _subjectFilter = 'linked'); unawaited(_loadList()); }),
                const SizedBox(width: 6),
                _chip(context, '未关联主体', _subjectFilter == 'unlinked', () { setState(() => _subjectFilter = 'unlinked'); unawaited(_loadList()); }),
              ]),
            ),
          ],
          if (_tab == _BizTab.settlement) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (value, label) in const [('', '全部'), ('configured', '已配置'), ('unconfigured', '未配置'), ('expiring', '30 天内到期')]) ...[
                  if (value.isNotEmpty) const SizedBox(width: 6),
                  _chip(context, label, _settleConfigured == value, () {
                    setState(() => _settleConfigured = value);
                    unawaited(_loadList());
                  }),
                ],
              ]),
            ),
          ],
          if (_searching) ...[const SizedBox(height: 8), _searchField(context)],
          const SizedBox(height: 10),
          _content(context),
        ],
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    const tabs = [(_BizTab.product, '产品'), (_BizTab.partner, '合作主体'), (_BizTab.settlement, '结算'), (_BizTab.proposal, '提案落地'), (_BizTab.link, '对接')];
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _ln(context, _kLine), width: 0.8))),
      child: Row(
        children: [
          for (final (tab, label) in tabs)
            Expanded(
              child: Semantics(
                button: true,
                selected: _tab == tab,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _switchTab(tab),
                  child: SizedBox(
                    height: 44,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          label,
                          style: _sans(
                            context,
                            size: 13,
                            weight: _tab == tab ? FontWeight.w700 : FontWeight.w500,
                            color: _tab == tab ? _kInk : _kMute,
                          ),
                        ),
                        const SizedBox(height: 7),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _tab == tab ? 20 : 0,
                          height: 2.5,
                          decoration: BoxDecoration(color: _fg(context, _kPurple), borderRadius: BorderRadius.circular(2)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool on, VoidCallback onTap, {IconData? trailing}) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _bg(context, on ? _kLavender : Colors.white),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _ln(context, on ? const Color(0xFFC9BCF3) : _kEdge), width: 0.9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: _sans(context, size: 12, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? _kDeep : _kInk2)),
              if (trailing != null) ...[
                const SizedBox(width: 2),
                Icon(trailing, size: 15, color: _fg(context, on ? _kDeep : _kInk2)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterRow(BuildContext context) {
    void pick(VoidCallback change) {
      setState(change);
      unawaited(_loadList());
    }

    final chips = <Widget>[
      ...switch (_tab) {
        _BizTab.product => [
          _chip(context, '渠道产品', _productSide == 'channel', () => pick(() => _productSide = 'channel')),
          _chip(context, '供应商产品', _productSide == 'supplier', () => pick(() => _productSide = 'supplier')),
          if (_platform.isNotEmpty)
            _chip(context, _platformLabel(), true, () => pick(() => _platform = ''), trailing: Icons.close_rounded),
        ],
        _BizTab.partner => [
          _chip(context, '渠道', _partnerKind == 'channel', () => pick(() => _partnerKind = 'channel')),
          _chip(context, '供应商', _partnerKind == 'supplier', () => pick(() => _partnerKind = 'supplier')),
          _chip(context, '推广商', _partnerKind == 'promoter', () => pick(() => _partnerKind = 'promoter')),
        ],
        _BizTab.settlement => [
          _chip(context, '渠道侧', _settleSide == 'channel', () => pick(() => _settleSide = 'channel')),
          _chip(context, '供应商侧', _settleSide == 'supplier', () => pick(() => _settleSide = 'supplier')),
        ],
        _BizTab.proposal => [
          _chip(context, '全部', _proposalKind.isEmpty, () => pick(() => _proposalKind = '')),
          _chip(context, '销售', _proposalKind == 'sales', () => pick(() => _proposalKind = 'sales')),
          _chip(context, '采购', _proposalKind == 'purchase', () => pick(() => _proposalKind = 'purchase')),
        ],
        _BizTab.link => [
          _chip(context, '推送', _linkView == 'push', () => pick(() => _linkView = 'push')),
          _chip(context, '结算回传', _linkView == 'return', () => pick(() => _linkView = 'return')),
        ],
      },
    ];
    final canSearch = _tab == _BizTab.product || _tab == _BizTab.partner || _tab == _BizTab.settlement;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  chips[i],
                ],
              ],
            ),
          ),
        ),
        if (_tab == _BizTab.product) ...[
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: '按业务平台筛选',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickPlatform,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _bg(context, _platform.isNotEmpty ? _kLavender : Colors.white),
                  shape: BoxShape.circle,
                  border: Border.all(color: _ln(context, _platform.isNotEmpty ? const Color(0xFFC9BCF3) : _kEdge), width: 0.9),
                ),
                child: Icon(Icons.tune_rounded, size: 16, color: _fg(context, _kDeep)),
              ),
            ),
          ),
        ],
        if (canSearch) ...[
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: _searching ? '收起搜索' : '搜索',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _searching = !_searching);
                if (!_searching && _keyword.isNotEmpty) {
                  _searchCtl.clear();
                  _keyword = '';
                  unawaited(_loadList());
                }
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _bg(context, _searching ? _kLavender : Colors.white),
                  shape: BoxShape.circle,
                  border: Border.all(color: _ln(context, _kEdge), width: 0.9),
                ),
                child: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, size: 16, color: _fg(context, _kDeep)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final hint = _tab == _BizTab.product || _tab == _BizTab.settlement ? '产品名称或编码' : '名称、简称或编码';
    return TextField(
      controller: _searchCtl,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: _sans(context, size: 13.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: _sans(context, size: 13, color: _kMute),
        prefixIcon: Icon(Icons.search_rounded, size: 17, color: _fg(context, _kMute)),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        filled: true,
        fillColor: _bg(context, _kPanel),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
      onSubmitted: (v) {
        _keyword = v.trim();
        unawaited(_loadList());
      },
    );
  }

  String _platformLabel() {
    if (_platform.isEmpty) return '业务平台';
    for (final p in _list(_overview?['platforms'])) {
      if (_s(p['code']) == _platform) return _s(p['name']).isEmpty ? _platform : _s(p['name']);
    }
    return _platform;
  }

  Future<void> _pickPlatform() async {
    final platforms = _list(_overview?['platforms']);
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: _bg(context, Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Text('业务平台', style: _sans(ctx, size: 15, weight: FontWeight.w700)),
            ),
            for (final p in [<String, dynamic>{'code': '', 'name': '全部业务平台'}, ...platforms])
              ListTile(
                dense: true,
                title: Text(_s(p['name']).isEmpty ? _s(p['code']) : _s(p['name']), style: _sans(ctx, size: 14)),
                subtitle: _s(p['code']).isEmpty ? null : Text(_s(p['code']), style: _sans(ctx, size: 11, color: _kMute)),
                trailing: _s(p['code']) == _platform ? Icon(Icons.check_rounded, color: _fg(ctx, _kPurple), size: 18) : null,
                onTap: () => Navigator.of(ctx).pop(_s(p['code'])),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _platform || !mounted) return;
    setState(() => _platform = picked);
    unawaited(_loadList());
  }

  // ───────────── 列表 ─────────────

  Widget _content(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))),
      );
    }
    if (_listError != null) return _inlineError(context, _listError!, _loadList);
    final children = <Widget>[
      if (_tab == _BizTab.link) _linkHead(context),
      for (var i = 0; i < _items.length; i++)
        (switch (_tab) {
          _BizTab.product => _productCard(context, _items[i], i + 1),
          _BizTab.partner => _partnerCard(context, _items[i]),
          _BizTab.settlement => _settlementCard(context, _items[i], i + 1),
          _BizTab.proposal => _proposalCard(context, _items[i]),
          _BizTab.link => _linkRow(context, _items[i]),
        }),
    ];
    if (_items.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(_emptyText(), style: _sans(context, size: 12.5, color: _kMute))),
      ));
    }
    final total = _i(_listMeta['total']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
        if (_tab != _BizTab.link && total != null && _items.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (_hasMore)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(
                  _loadingMore ? '加载中…' : '加载更多 · 已显示 ${_items.length} / ${_count(total)}',
                  style: _sans(context, size: 12.5, weight: FontWeight.w600, color: _kDeep),
                ),
              ),
            )
          else
            Center(child: Text('共 ${_count(total)} 条', style: _sans(context, size: 11.5, color: _kMute))),
        ],
      ],
    );
  }

  String _emptyText() => switch (_tab) {
    _BizTab.product => _keyword.isNotEmpty
        ? '没有找到「$_keyword」'
        : (_productSide == 'channel' && _chain.isNotEmpty ? '「${_chainLabel(_chain)}」下没有产品' : '没有产品'),
    _BizTab.partner => _keyword.isEmpty ? '没有记录' : '没有找到「$_keyword」',
    _BizTab.settlement => _keyword.isNotEmpty
        ? '没有找到「$_keyword」'
        : switch (_settleConfigured) {
            'configured' => '没有已配置结算的产品',
            'unconfigured' => '所有产品都已配置结算',
            'expiring' => '30 天内没有到期的结算规则',
            _ => '没有产品',
          },
    _BizTab.proposal => '还没有沙丘提案入站记录',
    _BizTab.link => _linkView == 'push' ? '今天没有推送失败' : '今天还没有结算回传批次',
  };

  // ───────────── 产品 · 链路筛选 ─────────────

  /// 与链路盘四圈一一对应的累积筛选：全部 / 已连接 / 双端生效 / 已配结算。
  /// 从底部结论进入的「缺口」分段（未连接供给 / 未双端生效 / 未配结算）以一个可关闭的标签显示。
  Widget _chainFilter(BuildContext context) {
    final c = _chainCounts;
    final total = _i(c?['total']), connected = _i(c?['connected']), usable = _i(c?['usable']), settled = _i(c?['settled']);
    int? minus(int? a, int? b) => a == null || b == null ? null : a - b;
    final counts = <String, int?>{
      '': total,
      'connected': connected,
      'usable': usable,
      _kChainThrough: settled,
      'unconnected': minus(total, connected),
      'half': minus(connected, usable),
      'unsettled': minus(usable, settled),
    };
    final leak = _kChainLeakKeys.contains(_chain);
    final keys = [..._kRingKeys, if (leak) _chain];
    void pick(String key) {
      if (_chain == key) return;
      setState(() => _chain = key);
      unawaited(_loadList());
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _segChip(
              context,
              _chainLabel(keys[i]),
              counts[keys[i]],
              on: _chain == keys[i],
              leakColor: _kChainLeakKeys.contains(keys[i]) ? _chainSeg(keys[i]).$2 : null,
              onTap: () => pick(_kChainLeakKeys.contains(keys[i]) ? '' : keys[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segChip(BuildContext context, String label, int? count, {required bool on, required VoidCallback onTap, Color? leakColor}) {
    return Semantics(
      button: true,
      selected: on,
      label: '$label ${_count(count)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _bg(context, on ? _kLavender : Colors.white),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _ln(context, on ? const Color(0xFFC9BCF3) : _kEdge), width: 0.9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leakColor != null) ...[
                Container(width: 6, height: 6, decoration: BoxDecoration(color: _fg(context, leakColor), shape: BoxShape.circle)),
                const SizedBox(width: 5),
              ],
              Text(label, style: _sans(context, size: 12, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? _kDeep : _kInk2)),
              const SizedBox(width: 5),
              Text(_count(count), style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: _fg(context, on ? _kDeep : _kInk))),
              if (leakColor != null) ...[
                const SizedBox(width: 3),
                Icon(Icons.close_rounded, size: 13, color: _fg(context, _kDeep)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _productCard(BuildContext context, Map<String, dynamic> p, int index) =>
      _bizProductCard(context, p, index, fallbackSide: _productSide);

  Widget _settlementCard(BuildContext context, Map<String, dynamic> p, int index) =>
      _bizSettlementCard(context, p, index, fallbackSide: _settleSide);

  Widget _partnerCard(BuildContext context, Map<String, dynamic> p) => _bizPartnerCard(context, p);

  Widget _proposalCard(BuildContext context, Map<String, dynamic> p) {
    final status = _s(p['status']);
    final kind = switch (_s(p['kind'])) {
      'sales' => '销售',
      'purchase' => '采购',
      final k => k.isEmpty ? '提案' : k,
    };
    final steps = p['steps'] is List ? (p['steps'] as List).map(_s).toList() : const <String>[];
    const labels = ['终审', '入站', '建档', '推送'];
    final ch = _map(p['channelProducts']);
    final sp = _map(p['supplierProducts']);
    final failed = _s(p['inboundStatus']).toUpperCase() == 'FAILED';
    String note;
    if (failed) {
      note = _s(p['inboundMessage']).isEmpty ? '资管入站失败' : _s(p['inboundMessage']);
    } else {
      final parts = <String>[];
      final chTotal = _i(ch['total']) ?? 0;
      final spTotal = _i(sp['total']) ?? 0;
      if (chTotal > 0) parts.add('渠道产品 $chTotal');
      if (spTotal > 0) parts.add('供应商产品 $spTotal');
      final eff = (_i(ch['effective']) ?? 0) + (_i(sp['effective']) ?? 0);
      final pend = (_i(ch['pending']) ?? 0) + (_i(sp['pending']) ?? 0);
      if (chTotal + spTotal > 0) {
        parts.add(eff == chTotal + spTotal ? '全部生效' : '生效 $eff${pend > 0 ? ' · 待审核 $pend' : ''}');
      } else {
        parts.add('资管里还没有关联这个提案的产品');
      }
      final pushes = _i(p['pushSuccess']);
      if (pushes != null && pushes > 0) parts.add('推送成功 $pushes 次');
      note = parts.join(' · ');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ln(context, _kEdge), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _tag(context, kind, _Tone.grey),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _s(p['code']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_s(p['name']).isEmpty ? '—' : _s(p['name']), style: _sans(context, size: 13.5, weight: FontWeight.w700, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _tag(context, status.isEmpty ? '—' : status, _proposalTone(status)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _stepCell(context, labels[i], i < steps.length ? steps[i] : 'wait')),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(note, style: _sans(context, size: 11.5, color: failed ? _kCoral : _kInk2, height: 1.35)),
          if (_s(p['inboundTime']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('入站 ${_s(p['inboundTime'])}', style: _sans(context, size: 10.5, color: _kMute)),
          ],
        ],
      ),
    );
  }

  Widget _stepCell(BuildContext context, String label, String state) {
    final (Widget mark, String said) = switch (state) {
      'done' => (_dot(context, _kPurple, Icons.check_rounded, Colors.white), '完成'),
      'fail' => (_dot(context, const Color(0xFFBC5C40), Icons.priority_high_rounded, Colors.white), '失败'),
      'doing' => (_dot(context, _kCopperSoft, Icons.more_horiz_rounded, _kCopper), '进行中'),
      'unknown' => (_dot(context, _kGreySoft, Icons.question_mark_rounded, _kGrey), '暂时查不到'),
      _ => (
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _ln(context, const Color(0xFFC7C7CF)), width: 1.3),
          ),
        ),
        '未开始',
      ),
    };
    return Semantics(
      label: '$label$said',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(11)),
        child: Column(
          children: [
            mark,
            const SizedBox(height: 5),
            Text(label, style: _sans(context, size: 11.5, color: _kInk2)),
          ],
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, Color bg, IconData icon, Color fg) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(color: _fg(context, bg), shape: BoxShape.circle),
    child: Icon(icon, size: 13, color: fg),
  );

  Widget _linkHead(BuildContext context) {
    final push = _linkView == 'push';
    final total = _i(_listMeta['total']);
    final failed = _i(_listMeta['failed']);
    final capped = _listMeta['capped'] == true;
    String pct = '';
    if (push && total != null && total > 0 && failed != null && failed > 0) {
      final v = failed * 100 / total;
      pct = ' · 占 ${v < 0.1 ? '<0.1' : v.toStringAsFixed(1)}%';
    }
    Widget box(String label, String value, {bool alert = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
        decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(13)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _sans(context, size: 10.5, color: _kMute)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: _num(context, size: 20, color: alert ? _kCoral : _kInk)),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            box(push ? '今日推送' : '今日回传批次', '${_count(total)}${capped && total != null ? '+' : ''}'),
            const SizedBox(width: 8),
            box(push ? '失败$pct' : '未完全成功', _count(failed), alert: (failed ?? 0) > 0),
          ],
        ),
        if (_listMeta['partial'] == true) ...[
          const SizedBox(height: 6),
          Text('部分数据这次没查到，下拉可重试', style: _sans(context, size: 10.5, color: _kMute)),
        ],
      ],
    );
  }

  Widget _linkRow(BuildContext context, Map<String, dynamic> r) {
    final today = _s(_listMeta['today']);
    if (_linkView == 'push') {
      final (label, tone) = _pushStatus(_s(r['pushStatus']));
      final meta = [
        _s(r['productCode']),
        _s(r['platformCode']),
        if (_s(r['httpStatus']).isNotEmpty) 'HTTP ${_s(r['httpStatus'])}',
      ].where((e) => e.isNotEmpty).join(' · ');
      final retry = _i(r['retryCount']) ?? 0;
      final exhausted = _s(r['retryExhausted']) == '1' || r['retryExhausted'] == true;
      final msg = [
        if (_s(r['message']).isNotEmpty) _s(r['message']),
        if (retry > 0) '已重试 $retry 次${exhausted ? '（用尽）' : ''}',
      ].join(' · ');
      return _eventRow(context, '${_pushType(_s(r['pushType']))} · $label', tone, _when(r['createTime'], today), meta, msg);
    }
    final (label, tone) = _returnStatus(_s(r['processStatus']));
    final meta = [
      if (_s(r['statDate']).isNotEmpty) '统计日 ${_date(r['statDate'])}',
      _s(r['syncNo']),
    ].where((e) => e.isNotEmpty).join(' · ');
    final counts = [
      if (_i(r['successCount']) != null) '成功 ${_count(_i(r['successCount']))}',
      if ((_i(r['failedCount']) ?? 0) > 0) '失败 ${_count(_i(r['failedCount']))}',
      if (_s(r['lastErrorMessage']).isNotEmpty) _s(r['lastErrorMessage']),
    ].join(' · ');
    return _eventRow(context, '${_s(r['syncSource']).isEmpty ? '回传' : _s(r['syncSource'])} · $label', tone, _when(r['createTime'], today), meta, counts);
  }

  Widget _eventRow(BuildContext context, String title, _Tone tone, String time, String meta, String msg) {
    final (fg, _) = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ln(context, _kEdge), width: 0.9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: _fg(context, fg), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: _sans(context, size: 13.5, weight: FontWeight.w700))),
                    Text(time, style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute))),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kInk2))),
                ],
                if (msg.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(msg, style: _sans(context, size: 11.5, color: tone == _Tone.coral ? _kCoral : (tone == _Tone.copper ? _kCopper : _kInk2), height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════ 产品详情（滑入） ═════════════════════════════

class LighthouseBizProductPage extends StatefulWidget {
  const LighthouseBizProductPage({
    super.key,
    required this.service,
    required this.side,
    required this.id,
    this.title = '',
  });

  final LighthouseService service;
  final String side;
  final String id;
  final String title;

  @override
  State<LighthouseBizProductPage> createState() => _BizProductState();
}

class _BizProductState extends State<LighthouseBizProductPage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await widget.service.fetchBizProductDetail(side: widget.side, id: widget.id);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errText(e));
    }
  }

  bool get _supplier => widget.side == 'supplier';

  @override
  Widget build(BuildContext context) {
    final bottom = dunesAppBottomNavContentPadding(context, fallback: 16) + 12;
    return Material(
      color: DunesColors.resolve(context, const Color(0xFFF6F5FA), role: DunesColorRole.surface),
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: _data == null
                ? (_error != null
                      ? Padding(padding: const EdgeInsets.all(16), child: _inlineError(context, _error!, _load))
                      : const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))))
                : RefreshIndicator(
                    color: _kPurple,
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(22, 4, 22, bottom),
                      children: _sections(context, _data!),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '返回业务',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                height: 36,
                padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                decoration: BoxDecoration(
                  color: _bg(context, Colors.white).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _ln(context, const Color(0x2E7B5CD8)), width: 0.6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left_rounded, size: 22, color: _fg(context, _kInk2)),
                    Text('业务', style: _sans(context, size: 14, weight: FontWeight.w600, color: _kInk2)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              _supplier ? '供应商产品' : '渠道产品',
              textAlign: TextAlign.center,
              style: _sans(context, size: 15, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 72),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context, Map<String, dynamic> d) {
    final p = _map(d['product']);
    final links = _map(d['links']);
    final productName = _s(p['productName']).isEmpty ? widget.title : _s(p['productName']);
    final out = <Widget>[_detailChain(context, d), _hero(context, p, d)];
    final proposal = _map(d['proposal']);
    if (_s(proposal['code']).isNotEmpty) {
      out.add(_card(context, null, [
        _kv(context, '来自沙丘提案', _s(proposal['name']).isEmpty ? _s(proposal['code']) : '${_s(proposal['name'])} · ${_s(proposal['code'])}'),
      ]));
    }
    if (_supplier) {
      // 优先用 links.usedBy（带渠道），没有时退回基础详情的 channelProducts。
      final used = _list(links['usedBy']);
      final ch = used.isNotEmpty ? used : _list(d['channelProducts']);
      out.add(_card(context, '被哪些渠道产品采用 · ${ch.length} 个', [
        if (ch.isEmpty) _emptyLine(context, '还没有渠道产品用它做货源'),
        for (final c in ch)
          _linkRow(
            context,
            onTap: () => _openBizProduct(context, 'channel', _s(c['id']), _s(c['productName'])),
            child: _rankedRow(
              context,
              rank: _s(c['priority']),
              title: _s(c['productName']).isEmpty ? '—' : _s(c['productName']),
              sub: [_s(c['channelName']), _s(c['productCode']), _s(c['syncSource']), if (_s(c['submitStatus']).isNotEmpty) _submitStatus(_s(c['submitStatus'])).$1]
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              value: _yuan(c['cost']),
              valueLabel: '成本',
            ),
          ),
      ]));
    } else {
      // links.sources 带供应商产品、供应商与合作主体；没有时退回基础详情的 sources。
      final linked = _list(links['sources']);
      final src = linked.isNotEmpty ? linked : _list(d['sources']);
      out.add(_card(context, '货源 · ${src.length} 个', [
        if (src.isEmpty) _emptyLine(context, '还没有配置货源'),
        for (var i = 0; i < src.length; i++)
          _linkRow(
            context,
            onTap: _s(src[i]['supplierId']).isEmpty
                ? null
                : () => _openBizPartner(context, 'supplier', _s(src[i]['supplierId']), name: _s(src[i]['supplierName'])),
            child: _rankedRow(
              context,
              rank: _s(src[i]['priority']).isEmpty ? '${i + 1}' : _s(src[i]['priority']),
              first: i == 0,
              title: _s(src[i]['supplierName']).isNotEmpty ? _s(src[i]['supplierName']) : (_s(src[i]['relSupplier']).isEmpty ? '—' : _s(src[i]['relSupplier'])),
              sub: linked.isEmpty
                  ? [_s(src[i]['realSupplierCode']), if (_s(src[i]['isActive']) == '0') '停用'].where((e) => e.isNotEmpty).join(' · ')
                  : [
                      if (_s(src[i]['supplierProductName']).isNotEmpty) _s(src[i]['supplierProductName']),
                      _s(src[i]['subjectName']).isEmpty ? '主体未关联' : '主体 ${_subjectDisplay(src[i]['subjectName'])}',
                      switch (_s(src[i]['state'])) {
                        'effective' => '生效',
                        'pending' => '待审核',
                        'disabled' => '已停用',
                        'broken' => '供应商产品已删除',
                        _ => '',
                      },
                    ].where((e) => e.isNotEmpty).join(' · '),
              value: _yuan(src[i]['cost']),
              valueLabel: '成本',
            ),
          ),
        if (src.isNotEmpty) _footnote(context, '数字是优先级，越小越先供货；点货源看供应商。'),
      ]));
    }
    final items = _list(d['settlementItems']);
    out.add(_card(context, '结算规则 · ${_supplier ? '供应商侧' : '渠道侧'}', [
      if (items.isEmpty) _emptyLine(context, '还没有结算行'),
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Divider(height: 18, thickness: 0.6, color: _ln(context, _kLine)),
        ..._settlementRows(context, items[i]),
      ],
      _linkRow(
        context,
        onTap: () => _openBizSettlement(context, widget.side, widget.id, productName),
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Row(
            children: [
              Text(items.isEmpty ? '去结算详情' : '结算详情 · 时间线与主体核对', style: _sans(context, size: 12, weight: FontWeight.w600, color: _kDeep)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 16, color: _fg(context, _kDeep)),
            ],
          ),
        ),
      ),
    ]));
    final rules = _list(d['priceRules']);
    if (rules.isNotEmpty) {
      out.add(_card(context, '价格规则 · ${rules.length} 条', [
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_s(r['ruleName']).isEmpty ? '—' : _s(r['ruleName']), style: _sans(context, size: 13.5, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        [_s(r['ruleCode']), if (_s(r['effectiveStartTime']).isNotEmpty) '${_date(r['effectiveStartTime'])} 起'].where((e) => e.isNotEmpty).join(' · '),
                        style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute)),
                      ),
                    ],
                  ),
                ),
                _tag(context, _s(r['status']) == '1' ? '启用' : (_s(r['status']) == '0' ? '停用' : (_s(r['status']).isEmpty ? '—' : _s(r['status']))),
                    _s(r['status']) == '1' ? _Tone.purple : _Tone.grey),
              ],
            ),
          ),
      ]));
    }
    final pushes = _list(d['pushes']);
    out.add(_card(context, '最近推送到业务平台', [
      if (pushes.isEmpty) _emptyLine(context, '没有推送记录'),
      for (final r in pushes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: _fg(context, _toneColors(_pushStatus(_s(r['pushStatus'])).$2).$1), shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_pushType(_s(r['pushType']))} · ${_pushStatus(_s(r['pushStatus'])).$1}', style: _sans(context, size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [_s(r['createTime']), _s(r['platformCode']), if (_s(r['httpStatus']).isNotEmpty) 'HTTP ${_s(r['httpStatus'])}']
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                      style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute)),
                    ),
                    if (_s(r['pushStatus']).toUpperCase() == 'FAILED' && _s(r['message']).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_s(r['message']), style: _sans(context, size: 11.5, color: _kCoral)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    ]));
    return [
      for (var i = 0; i < out.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        out[i],
      ],
    ];
  }

  /// 把详情数据整理成和列表卡片同形状的 map，交给同一个 [_productChain]，
  /// 保证一级卡片和二级详情顶部的关系链、状态说明逐字一致。
  Map<String, dynamic> _cardLike(Map<String, dynamic> d) {
    final p = _map(d['product']);
    final links = _map(d['links']);
    final chain = _map(links['chain']);
    final partner = _map(links['partner']);
    final rules = _list(d['settlementItems']);
    final first = rules.isEmpty ? const <String, dynamic>{} : rules.first;
    // 与后端 earliestFutureExpire 同口径：尚未到期的规则里最早的到期时间。
    var expire = '';
    final now = DateTime.now();
    for (final r in rules) {
      final e = _s(r['expireTime']);
      final t = DateTime.tryParse(e);
      if (t == null || t.isBefore(now)) continue;
      if (expire.isEmpty || e.compareTo(expire) < 0) expire = e;
    }
    final used = _list(links['usedBy']);
    return <String, dynamic>{
      'id': widget.id,
      'name': _s(p['productName']).isEmpty ? widget.title : _s(p['productName']),
      'side': widget.side,
      'submitStatus': p['submitStatus'],
      'status': p['status'],
      'settlementCount': rules.length,
      'settleMethodCode': first['settleMethod'],
      'settleMethod': first['settleMethodLabel'],
      'settlementRatio': first['settlementRatio'],
      'settlementUnitPrice': first['unitPrice'],
      'settlementExpire': expire,
      if (_supplier) ...{
        'chainKnown': true,
        'chainSubject': partner['subjectName'],
        'chainSubjectId': partner['subjectId'],
        'chainSupplier': partner['name'],
        'chainSupplierId': partner['id'],
        'usedBy': used.isNotEmpty ? used.length : _list(d['channelProducts']).length,
      } else ...{
        'chainKnown': chain.isNotEmpty,
        'chainBreak': chain['break'],
        'chainReason': chain['reason'],
        'supplierProductState': chain['supplierProductState'],
        'chainSubject': chain['subject'],
        'chainSubjectId': chain['subjectId'],
        'chainSupplier': chain['supplier'],
        'chainSupplierId': chain['supplierId'],
      },
    };
  }

  /// 顶部关系链：和列表卡片同一条——法人主体 › 供应商 › 本产品 › 结算，下面是同一句状态说明。
  /// 渠道产品的渠道放在标题下的标签里（见 [_channelChip]），不进这条链。
  Widget _detailChain(BuildContext context, Map<String, dynamic> d) {
    final (segs, hint, hintColor) = _productChain(context, _cardLike(d), widget.side);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _relationChain(context, [
          ...segs.take(2),
          const _ChainSeg('产品', '本产品', current: true),
          ...segs.skip(2),
        ]),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: _chainHint(context, hint, hintColor),
          ),
      ],
    );
  }

  /// 渠道产品标题下的渠道标签：点进渠道详情；渠道没关联法人主体时顺带标出。
  Widget _channelChip(BuildContext context, Map<String, dynamic> partner) {
    final linked = _s(partner['subjectId']).isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '渠道 ${_s(partner['name'])}，查看渠道',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openBizPartner(context, 'channel', _s(partner['id']), name: _s(partner['name'])),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
            decoration: BoxDecoration(color: _bg(context, _kLavender), borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('渠道 · ${_s(partner['name'])}', style: _sans(context, size: 11, weight: FontWeight.w600, color: _kDeep)),
                const SizedBox(width: 6),
                Text(
                  linked ? '法人主体 ${_subjectDisplay(partner['subjectName'])}' : '法人主体未关联',
                  style: _sans(context, size: 10.5, color: linked ? _kInk2 : _kCoral),
                ),
                Icon(Icons.chevron_right_rounded, size: 15, color: _fg(context, _kDeep)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 详情里可点的一行：有去处时整行可点，并在右侧露出箭头。
  Widget _linkRow(BuildContext context, {required Widget child, VoidCallback? onTap}) {
    if (onTap == null) return child;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(child: child),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: _fg(context, _kMute)),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, Map<String, dynamic> p, Map<String, dynamic> d) {
    final name = _s(p['productName']).isEmpty ? (widget.title.isEmpty ? '—' : widget.title) : _s(p['productName']);
    final (submitLabel, submitTone) = _submitStatus(_s(p['submitStatus']));
    final status = _productStatus(widget.side, _s(p['status']));
    final partner = _supplier ? _s(p['supplierName']) : _s(p['channelName']);
    final sub = [partner, _s(p['projectName']), _s(p['syncSource'])].where((e) => e.isNotEmpty).join(' · ');
    final firstSource = _list(d['sources']).isNotEmpty ? _list(d['sources']).first : const <String, dynamic>{};
    final cells = _supplier
        ? <(String, String)>[
            ('单价', _yuan(p['unitPrice'])),
            ('面值', _yuanFromFen(p['faceValue'])),
            ('门槛金额', _yuan(p['thresholdAmount'])),
          ]
        : <(String, String)>[
            ('面值', _yuan(p['denomination'])),
            ('单价', _yuan(p['unitPrice'])),
            ('首选货源成本', firstSource.isEmpty ? '未配置' : _yuan(firstSource['cost'])),
          ];
    final info = <(String, String)>[
      if (!_supplier)
        ('渠道分类', [_s(p['channelCategoryL1Name']), _s(p['channelCategoryL2Name'])].where((e) => e.isNotEmpty).join(' / ')),
      if (_supplier) ('产品分类', _s(p['categoryName'])),
      ('产品类型', _s(p['productTypeName'])),
      ('产品编码', _s(p['productCode'])),
      ('状态', status),
    ].where((e) => e.$2.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(name, style: _sans(context, size: 19, weight: FontWeight.w700, height: 1.3))),
              const SizedBox(width: 8),
              _tag(context, submitLabel, submitTone),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub, style: _sans(context, size: 11.5, color: _kMute)),
          ],
          if (!_supplier && _s(_map(_map(d['links'])['partner'])['id']).isNotEmpty) ...[
            const SizedBox(height: 8),
            _channelChip(context, _map(_map(d['links'])['partner'])),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                    decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(11)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cells[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: _kMute)),
                        const SizedBox(height: 3),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(cells[i].$2, style: _num(context, size: 15.5))),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (info.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 0.6, color: _ln(context, _kLine)),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final (k, v) in info)
                      SizedBox(
                        width: w,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k, style: _sans(context, size: 10.5, color: _kMute)),
                            const SizedBox(height: 2),
                            Text(v, style: _sans(context, size: 13, weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _settlementRows(BuildContext context, Map<String, dynamic> it) {
    final method = _s(it['settleMethod']);
    final value = switch (method) {
      '1' => '比例 ${_plain(it['settlementRatio'])}',
      '2' => '单价 ${_yuan(it['unitPrice'])}',
      '5' => '${_yuan(it['unitPrice'])} × ${_plain(it['settlementRatio'])}',
      _ => '',
    };
    final effective = _s(it['effectiveTime']);
    final expire = _s(it['expireTime']);
    return [
      _kv(context, '账单类型', _s(it['billTypeL3Name'])),
      _kv(context, '结算方式', [_s(it['settleMethodLabel']), value].where((e) => e.isNotEmpty).join(' · ')),
      if (_s(it['formulaName']).isNotEmpty) _kv(context, '计算公式', _s(it['formulaName'])),
      if (_s(it['thresholdAmount']).isNotEmpty) _kv(context, '门槛金额', _yuan(it['thresholdAmount'])),
      _kv(context, '我方 / 对方主体', [_s(it['ourEntity']), _s(it['counterpartyEntity'])].map((e) => e.isEmpty ? '—' : e).join(' / ')),
      _kv(
        context,
        '生效期',
        effective.isEmpty && expire.isEmpty
            ? '—'
            : '${effective.isEmpty ? '—' : _date(effective)} 起${expire.isEmpty ? ' · 长期' : ' · 至 ${_date(expire)}'}',
      ),
    ];
  }

  Widget _card(BuildContext context, String? title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ln(context, _kEdge), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title, style: _sans(context, size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 6),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: Text(k, style: _sans(context, size: 12.5, color: _kMute))),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            textAlign: TextAlign.right,
            style: _sans(context, size: 12.5, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _rankedRow(
    BuildContext context, {
    required String rank,
    required String title,
    required String sub,
    required String value,
    required String valueLabel,
    bool first = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _fg(context, first ? _kInk : _kGreySoft), shape: BoxShape.circle),
            child: Text(
              rank.isEmpty ? '·' : rank,
              style: LhTypography.mono(context: context, size: 11, weight: FontWeight.w700, color: first ? Colors.white : _fg(context, _kInk2)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 13.5, weight: FontWeight.w600)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: _kMute)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: _num(context, size: 14)),
              Text(valueLabel, style: _sans(context, size: 10, color: _kMute)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyLine(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(text, style: _sans(context, size: 12, color: _kMute)),
  );

  Widget _footnote(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: _sans(context, size: 10.5, color: _kMute)),
  );
}

// ═════════════════════════════ 公共小件 ═════════════════════════════

Widget _tapCard(BuildContext context, {required String label, required VoidCallback onTap, required Widget child}) {
  return Semantics(
    button: true,
    label: label,
    child: Material(
      color: _bg(context, Colors.white),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ln(context, _kEdge), width: 0.9),
          ),
          child: child,
        ),
      ),
    ),
  );
}

Widget _inlineError(BuildContext context, String message, Future<void> Function() retry) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center, style: _sans(context, size: 12.5, color: _kInk2)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => unawaited(retry()),
          child: Text('重试', style: _sans(context, size: 13, weight: FontWeight.w600, color: _kDeep)),
        ),
      ],
    ),
  );
}

// ═════════════════════════════ 共用卡片 ═════════════════════════════

Widget _bizIndexBadge(BuildContext context, String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
  decoration: BoxDecoration(color: _bg(context, _kLavender), borderRadius: BorderRadius.circular(5)),
  child: Text(text, style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w600, color: _fg(context, _kDeep), height: 1.1)),
);

Widget _bizCellGrid(BuildContext context, List<(String, String)> cells) {
  return Row(
    children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
            decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(11)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cells[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10, color: _kMute)),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(cells[i].$2, maxLines: 1, style: _num(context, size: 13)),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

/// 产品卡（业务首页与合作主体详情共用）：序号 / 名称 / 归属 + 迷你关系链（合作主体 › 供应商 › 结算），点标题进产品详情。
Widget _bizProductCard(BuildContext context, Map<String, dynamic> p, int index, {required String fallbackSide}) {
  final side = _s(p['side']).isEmpty ? fallbackSide : _s(p['side']);
  final (submitLabel, submitTone) = _submitStatus(_s(p['submitStatus']));
  final sub = [_s(p['partner']), _s(p['project']), _s(p['syncSource'])].where((e) => e.isNotEmpty).join(' · ');
  final status = _productStatus(side, _s(p['status']));
  final name = _s(p['name']).isEmpty ? '—' : _s(p['name']);
  final (segs, hint, hintColor) = _productChain(context, p, side);
  return _tapCard(
    context,
    label: '$name，查看详情',
    onTap: () => Navigator.of(context).pushNamed('/product', arguments: {'side': side, 'id': _s(p['id']), 'name': name}),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: _bizIndexBadge(context, index.toString().padLeft(2, '0'))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: _sans(context, size: 13.5, weight: FontWeight.w700, height: 1.3)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: _kMute)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_s(p['updateTime']).isNotEmpty) ...[
                  Text(
                    '更新于 ${_when(p['updateTime'], DateTime.now().toIso8601String().substring(0, 10))}',
                    maxLines: 1,
                    style: _sans(context, size: 10, color: _kMute),
                  ),
                  const SizedBox(height: 4),
                ],
                _tag(context, submitLabel, submitTone),
                if (status == '停用' || status == '待生效') ...[
                  const SizedBox(height: 4),
                  _tag(context, status, status == '停用' ? _Tone.grey : _Tone.copper),
                ],
              ],
            ),
          ],
        ),
        _miniChain(context, segs),
        if (hint != null) _chainHint(context, hint, hintColor),
      ],
    ),
  );
}

// ═════════════════════════════ 二级页面：合作主体详情 / 结算详情 / 主体页 ═════════════════════════════

/// 二级页面共用的顶栏：左「‹ 业务」返回，中间标题。
Widget _bizSubHeader(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    child: Row(
      children: [
        Semantics(
          button: true,
          label: '返回',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              height: 34,
              padding: const EdgeInsets.fromLTRB(4, 0, 11, 0),
              decoration: BoxDecoration(
                color: _bg(context, Colors.white).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: _ln(context, const Color(0x2E7B5CD8)), width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 21, color: _fg(context, _kInk2)),
                  Text('返回', style: _sans(context, size: 13, weight: FontWeight.w600, color: _kInk2)),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: Text(title, textAlign: TextAlign.center, style: _sans(context, size: 14.5, weight: FontWeight.w700))),
        const SizedBox(width: 72),
      ],
    ),
  );
}

Widget _bizSubPage(BuildContext context, {required String title, required Future<void> Function() onRefresh, required List<Widget> children}) {
  final bottom = dunesAppBottomNavContentPadding(context, fallback: 16) + 12;
  return Material(
    color: DunesColors.resolve(context, const Color(0xFFF6F5FA), role: DunesColorRole.surface),
    child: Column(
      children: [
        _bizSubHeader(context, title),
        Expanded(
          child: RefreshIndicator(
            color: _kPurple,
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _bizLoading() => const Padding(
  padding: EdgeInsets.symmetric(vertical: 40),
  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))),
);

Widget _bizSection(BuildContext context, String title, {int? count, String note = ''}) => Padding(
  padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title, style: _sans(context, size: 13, weight: FontWeight.w700)),
      if (count != null) ...[
        const SizedBox(width: 6),
        Text(_count(count), style: LhTypography.mono(context: context, size: 11, weight: FontWeight.w600, color: _fg(context, _kMute))),
      ],
      const Spacer(),
      if (note.isNotEmpty) Text(note, style: _sans(context, size: 10.5, color: _kMute)),
    ],
  ),
);

Widget _bizSpaced(List<Widget> items, {double gap = 8}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < items.length; i++) ...[
      if (i > 0) SizedBox(height: gap),
      items[i],
    ],
  ],
);

// ── 合作主体详情（渠道 / 供应商 / 推广商）──

class LighthouseBizPartnerPage extends StatefulWidget {
  const LighthouseBizPartnerPage({
    super.key,
    required this.service,
    required this.kind,
    required this.id,
    this.title = '',
    this.initial,
    this.initialTab = '',
  });

  final LighthouseService service;
  final String kind;
  final String id;
  final String title;
  final Map<String, dynamic>? initial;
  final String initialTab;

  @override
  State<LighthouseBizPartnerPage> createState() => _BizPartnerState();
}

class _BizPartnerState extends State<LighthouseBizPartnerPage> {
  static const _pageSize = 20;

  Map<String, dynamic>? _p;
  String? _pError;
  String _tab = 'product';
  final Map<String, List<Map<String, dynamic>>> _items = {'product': [], 'settle': []};
  final Map<String, int> _total = {'product': 0, 'settle': 0};
  final Map<String, int> _page = {'product': 1, 'settle': 1};
  final Set<String> _loaded = {};
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  String get _kind => widget.kind.isNotEmpty ? widget.kind : _s(_p?['kind']);
  String get _side => _kind == 'channel' ? 'channel' : 'supplier';
  String get _kindLabel => switch (_kind) {
    'channel' => '渠道',
    'promoter' => '推广商',
    _ => '供应商',
  };

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'settle' ? 'settle' : 'product';
    final init = widget.initial;
    if (init != null && init.containsKey('productCount')) {
      _p = init;
    } else {
      unawaited(_loadPartner());
    }
    unawaited(_loadList());
  }

  Future<void> _loadPartner() async {
    try {
      final d = await widget.service.fetchBizPartners(kind: _kind.isEmpty ? 'supplier' : _kind, id: widget.id, page: 1, size: 1);
      if (!mounted) return;
      final items = _list(d['items']);
      setState(() {
        _p = items.isEmpty ? const <String, dynamic>{} : items.first;
        _pError = items.isEmpty ? '没有找到这个$_kindLabel' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pError = _errText(e));
    }
  }

  Future<Map<String, dynamic>> _fetch(String tab, int page) => tab == 'settle'
      ? widget.service.fetchBizSettlements(side: _side, configured: 'configured', partnerId: widget.id, page: page, size: _pageSize)
      : widget.service.fetchBizProducts(side: _side, partnerId: widget.id, page: page, size: _pageSize);

  Future<void> _loadList() async {
    if (_kind == 'promoter') return;
    final tab = _tab;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _fetch(tab, 1);
      if (!mounted) return;
      setState(() {
        _items[tab] = _list(d['items']);
        _total[tab] = _i(d['total']) ?? _items[tab]!.length;
        _page[tab] = 1;
        _loaded.add(tab);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errText(e);
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore) return;
    final tab = _tab;
    setState(() => _loadingMore = true);
    try {
      final d = await _fetch(tab, (_page[tab] ?? 1) + 1);
      if (!mounted) return;
      setState(() {
        _page[tab] = (_page[tab] ?? 1) + 1;
        _items[tab]!.addAll(_list(d['items']));
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_errText(e))));
    }
  }

  void _switch(String tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (!_loaded.contains(tab)) unawaited(_loadList());
  }

  Future<void> _refresh() async {
    _loaded.clear();
    await Future.wait([_loadPartner(), _loadList()]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final children = <Widget>[];
    if (p == null) {
      children.add(_pError != null ? _inlineError(context, _pError!, _loadPartner) : _bizLoading());
    } else {
      final name = _s(p['name']).isEmpty ? (widget.title.isEmpty ? '—' : widget.title) : _s(p['name']);
      final linked = p['subjectLinked'] == true;
      final products = _i(p['productCount']) ?? 0;
      final settledN = _i(p['settledProducts']);
      final settled = settledN ?? (_total['settle'] ?? 0);
      children.add(_relationChain(context, [
        _ChainSeg(
          '法人主体',
          linked ? (_s(p['subjectName']).isEmpty ? '主体档案不可用' : _subjectDisplay(p['subjectName'])) : '未关联',
          tone: linked ? _SegTone.normal : _SegTone.bad,
          onTap: linked ? () => _openBizSubject(context, _s(p['subjectId']), _s(p['subjectName'])) : null,
        ),
        _ChainSeg(_kindLabel, name, current: true),
        if (_kind != 'promoter') ...[
          _ChainSeg('产品', '${_count(products)} 个', onTap: () => _switch('product')),
          _ChainSeg('结算', settledN == null ? '—' : '${_count(settled)} 个产品', onTap: () => _switch('settle')),
        ],
      ]));
      children
        ..add(const SizedBox(height: 10))
        ..add(_infoCard(context, p, name));
      if (_kind == 'promoter') {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('推广商按价格规则合作，规则明细暂未在 App 展示', style: _sans(context, size: 11.5, color: _kMute))),
        ));
      } else {
        children
          ..add(const SizedBox(height: 12))
          ..add(_tabs(context, products, settled))
          ..add(const SizedBox(height: 10))
          ..addAll(_listBody(context, products, settled));
      }
    }
    return _bizSubPage(context, title: _kindLabel, onRefresh: _refresh, children: children);
  }

  Widget _infoCard(BuildContext context, Map<String, dynamic> p, String name) {
    final (statusLabel, tone) = _partnerStatus(_s(p['status']));
    final products = _i(p['productCount']) ?? 0;
    final effective = _i(p['effectiveProductCount']) ?? 0;
    final settledN = _i(p['settledProducts']);
    final expiring = _i(p['expiringProducts']) ?? 0;
    String n(Object? v) => _i(v) == null ? '—' : '${_count(_i(v))} 个';
    final cells = <(String, String)>[
      ('审核生效产品', '${_count(effective)} 个'),
      if (_kind == 'channel') ('已贯通', n(p['throughProducts'])) else ('被渠道采用', n(p['usedProducts'])),
      ('结算覆盖', settledN == null ? '—' : _pct(settledN, products)),
    ];
    final lines = <String>[
      if (_s(p['sub']).isNotEmpty) _s(p['sub']) else if (_s(p['shortName']).isNotEmpty) _s(p['shortName']),
      if ((_i(p['provinceCount']) ?? 0) > 0) '覆盖 ${_i(p['provinceCount'])} 个省份',
      if (_s(p['syncSource']).isNotEmpty) '业务平台 · ${_s(p['syncSource'])}',
      if (expiring > 0) '$expiring 个产品的结算规则 30 天内到期',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _bg(context, _kLavender), borderRadius: BorderRadius.circular(10)),
                child: Text(name.characters.first, style: _sans(context, size: 14, weight: FontWeight.w700, color: _kDeep)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: _sans(context, size: 14, weight: FontWeight.w700, height: 1.3)),
                    for (final l in lines) ...[
                      const SizedBox(height: 2),
                      Text(l, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: _kMute)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _tag(context, statusLabel, tone),
            ],
          ),
          if (_kind != 'promoter') ...[
            const SizedBox(height: 12),
            _bizCellGrid(context, cells),
          ],
        ],
      ),
    );
  }

  Widget _tabs(BuildContext context, int products, int settled) {
    final tabs = [('product', '产品', products), ('settle', '结算', settled)];
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _ln(context, _kLine), width: 0.8))),
      child: Row(
        children: [
          for (final (key, label, n) in tabs)
            Expanded(
              child: Semantics(
                button: true,
                selected: _tab == key,
                label: '$label $n',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _switch(key),
                  child: SizedBox(
                    height: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: label, style: _sans(context, size: 13, weight: _tab == key ? FontWeight.w700 : FontWeight.w500, color: _tab == key ? _kInk : _kMute)),
                            TextSpan(text: ' ${_count(n)}', style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute))),
                          ]),
                        ),
                        const SizedBox(height: 7),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _tab == key ? 20 : 0,
                          height: 2.5,
                          decoration: BoxDecoration(color: _fg(context, _kPurple), borderRadius: BorderRadius.circular(2)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _listBody(BuildContext context, int products, int settled) {
    if (_loading && !_loaded.contains(_tab)) return [_bizLoading()];
    if (_error != null && !_loaded.contains(_tab)) return [_inlineError(context, _error!, _loadList)];
    final items = _items[_tab]!;
    final total = _total[_tab] ?? items.length;
    final out = <Widget>[];
    if (_tab == 'settle' && products > settled) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('还有 ${_count(products - settled)} 个产品未配结算', style: _sans(context, size: 10.5, color: _kMute)),
      ));
    }
    if (items.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(_tab == 'settle' ? '名下还没有配结算的产品' : '名下还没有产品', style: _sans(context, size: 12, color: _kMute))),
      ));
      return out;
    }
    out.add(_bizSpaced([
      for (var i = 0; i < items.length; i++)
        _tab == 'settle'
            ? _bizSettlementCard(context, items[i], i + 1, fallbackSide: _side)
            : _bizProductCard(context, items[i], i + 1, fallbackSide: _side),
    ]));
    out.add(const SizedBox(height: 10));
    if (items.length < total) {
      out.add(Center(
        child: TextButton(
          onPressed: _loadingMore ? null : _more,
          child: Text(
            _loadingMore ? '加载中…' : '加载更多 · 已显示 ${items.length} / ${_count(total)}',
            style: _sans(context, size: 12, weight: FontWeight.w600, color: _kDeep),
          ),
        ),
      ));
    } else {
      out.add(Center(child: Text('共 ${_count(total)} 个', style: _sans(context, size: 11, color: _kMute))));
    }
    return out;
  }
}

// ── 结算详情 ──

/// 一个产品的全部结算规则：关系链、规则时间线、逐条规则、对方主体核对。数据来自产品详情接口。
class LighthouseBizSettlementPage extends StatefulWidget {
  const LighthouseBizSettlementPage({super.key, required this.service, required this.side, required this.id, this.title = ''});

  final LighthouseService service;
  final String side;
  final String id;
  final String title;

  @override
  State<LighthouseBizSettlementPage> createState() => _BizSettlementState();
}

class _BizSettlementState extends State<LighthouseBizSettlementPage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await widget.service.fetchBizProductDetail(side: widget.side, id: widget.id);
      if (!mounted) return;
      setState(() => _data = d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errText(e));
    }
  }

  bool get _supplier => widget.side == 'supplier';

  /// 产品格下面那行：渠道产品写链路状态（与结算卡同口径），供应商产品写审核状态。
  String _productStateText(Map<String, dynamic> links) {
    final chain = _map(links['chain']);
    if (_supplier || chain.isEmpty) return '';
    final brk = _i(chain['break']) ?? -1;
    return brk < 0 ? '已贯通' : _chainSeg(_chainSegOfBreak(brk)).$1;
  }

  /// (状态名, 色调, 剩余天数)
  (String, _Tone) _ruleStatus(Map<String, dynamic> r) {
    final now = DateTime.now();
    final eff = DateTime.tryParse(_s(r['effectiveTime']));
    final exp = DateTime.tryParse(_s(r['expireTime']));
    if (eff != null && eff.isAfter(now)) return ('未生效', _Tone.grey);
    if (exp != null && exp.isBefore(now)) return ('已到期', _Tone.grey);
    final days = _daysUntil(r['expireTime']);
    if (days != null && days <= 30) return (days <= 0 ? '今天到期' : '$days 天到期', _Tone.copper);
    return ('生效中', _Tone.purple);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final children = <Widget>[];
    if (d == null) {
      children.add(_error != null ? _inlineError(context, _error!, _load) : _bizLoading());
    } else {
      final p = _map(d['product']);
      final links = _map(d['links']);
      final partner = _map(links['partner']);
      final rules = _list(d['settlementItems']);
      final name = _s(p['productName']).isEmpty ? widget.title : _s(p['productName']);
      final kindLabel = _supplier ? '供应商' : '渠道';
      final subjectName = _s(partner['subjectName']);
      children
        ..add(_relationChain(context, [
          _ChainSeg(
            '法人主体',
            subjectName.isEmpty ? '未关联' : _subjectDisplay(subjectName),
            tone: subjectName.isEmpty ? _SegTone.warn : _SegTone.normal,
            onTap: _s(partner['subjectId']).isEmpty ? null : () => _openBizSubject(context, _s(partner['subjectId']), subjectName),
          ),
          _ChainSeg(
            kindLabel,
            _s(partner['name']).isEmpty ? '—' : _s(partner['name']),
            onTap: () => _openBizPartner(context, _supplier ? 'supplier' : 'channel', _s(partner['id']), name: _s(partner['name'])),
          ),
          _ChainSeg(
            '产品',
            name.isEmpty ? '—' : name,
            sub: _productStateText(links),
            onTap: () => _openBizProduct(context, widget.side, widget.id, name),
          ),
          _ChainSeg('结算', '${rules.length} 条', current: true),
        ]))
        ..add(const SizedBox(height: 10))
        ..add(_summary(context, rules));
      if (rules.isNotEmpty) {
        children
          ..add(_bizSection(context, '规则', count: rules.length))
          ..add(_bizSpaced([for (final r in rules) _ruleCard(context, r)]))
          ..add(_bizSection(context, '主体核对', note: '规则里的对方主体 vs $kindLabel关联的法人主体'))
          ..add(_check(context, rules, partner, kindLabel));
      }
    }
    return _bizSubPage(context, title: '结算', onRefresh: _load, children: children);
  }

  Widget _summary(BuildContext context, List<Map<String, dynamic>> rules) {
    final statuses = [for (final r in rules) _ruleStatus(r).$1];
    final active = statuses.where((s) => s == '生效中' || s.endsWith('到期') && s != '已到期').length;
    final soon = statuses.where((s) => s.endsWith('天到期') || s == '今天到期').length;
    final now = DateTime.now();
    final y0 = DateTime(now.year);
    final y1 = DateTime(now.year + 1);
    final span = y1.difference(y0).inMinutes.toDouble();
    double frac(DateTime t) => (t.difference(y0).inMinutes / span).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bizCellGrid(context, [('规则', '${rules.length} 条'), ('生效中', '$active 条'), ('30 天内到期', '$soon 条')]),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('这个产品还没有结算规则', style: _sans(context, size: 12, color: _kMute)),
            )
          else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text('生效期', style: _sans(context, size: 12, weight: FontWeight.w700)),
                const Spacer(),
                Text('${now.year}', style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var m = 1; m <= 12; m++)
                  Expanded(child: Text('$m', style: LhTypography.mono(context: context, size: 8.5, color: _fg(context, _kMute)))),
              ],
            ),
            const SizedBox(height: 4),
            for (final r in rules) ...[
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 3, top: 4),
                child: Text(
                  [_s(r['billTypeL3Name']), _ruleShort(_s(r['settleMethod']), r['settlementRatio'], r['unitPrice'], _s(r['settleMethodLabel']))]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(context, size: 10, color: _kInk2),
                ),
              ),
              LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  final eff = DateTime.tryParse(_s(r['effectiveTime'])) ?? y0;
                  final exp = DateTime.tryParse(_s(r['expireTime'])) ?? y1;
                  final a = frac(eff), b = frac(exp);
                  final soonRule = _ruleStatus(r).$2 == _Tone.copper;
                  return SizedBox(
                    height: 16,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(8)))),
                        if (b > a)
                          Positioned(
                            left: w * a,
                            width: math.max(4.0, w * (b - a)),
                            top: 3,
                            height: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                gradient: LinearGradient(
                                  colors: soonRule
                                      ? [_fg(context, const Color(0xFFF2DDB8)), _fg(context, const Color(0xFFD9A24F))]
                                      : [_fg(context, const Color(0xFFC8D3FC)), _fg(context, const Color(0xFF8E72E2))],
                                ),
                              ),
                            ),
                          ),
                        Positioned(left: w * frac(now), top: -2, bottom: -2, width: 1, child: ColoredBox(color: _fg(context, _kCoral))),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _ruleCard(BuildContext context, Map<String, dynamic> r) {
    final (label, tone) = _ruleStatus(r);
    final eff = _s(r['effectiveTime']);
    final exp = _s(r['expireTime']);
    final value = _ruleShort(_s(r['settleMethod']), r['settlementRatio'], r['unitPrice'], '');
    Widget kv(String k, String v, {bool mono = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(k, style: _sans(context, size: 11, color: _kMute))),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              textAlign: TextAlign.right,
              style: mono
                  ? LhTypography.mono(context: context, size: 11, weight: FontWeight.w600, color: _fg(context, _kInk))
                  : _sans(context, size: 11, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ln(context, _kEdge), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_s(r['billTypeL3Name']).isEmpty ? '结算规则' : _s(r['billTypeL3Name']), style: _sans(context, size: 13, weight: FontWeight.w700)),
              ),
              _tag(context, label, tone),
            ],
          ),
          const SizedBox(height: 6),
          kv('结算方式', [_s(r['settleMethodLabel']), value].where((e) => e.isNotEmpty).join(' · '), mono: true),
          if (_s(r['formulaName']).isNotEmpty) kv('计算公式', _s(r['formulaName'])),
          if (_s(r['thresholdAmount']).isNotEmpty) kv('门槛金额', _yuan(r['thresholdAmount']), mono: true),
          kv('我方主体', _s(r['ourEntity'])),
          kv('对方主体', _s(r['counterpartyEntity'])),
          kv('生效期', '${eff.isEmpty ? '—' : _date(eff)} → ${exp.isEmpty ? '长期' : _date(exp)}', mono: true),
        ],
      ),
    );
  }

  Widget _check(BuildContext context, List<Map<String, dynamic>> rules, Map<String, dynamic> partner, String kindLabel) {
    final subjectId = _s(partner['subjectId']);
    final full = _s(partner['subjectFullName']);
    final short = _s(partner['subjectName']);
    final parties = {for (final r in rules) _s(r['counterpartyEntity'])}..remove('');
    bool same(String a) => a.trim().toLowerCase() == full.trim().toLowerCase() || a.trim().toLowerCase() == short.trim().toLowerCase();
    final String text;
    final Color color;
    final Color soft;
    VoidCallback? onTap;
    String action = '';
    if (subjectId.isEmpty) {
      text = '$kindLabel「${_s(partner['name'])}」还没有关联法人主体，无法核对规则里的对方主体${parties.isEmpty ? '' : '（${parties.join('、')}）'}是否同一法人。';
      color = _kCopper;
      soft = _kCopperSoft;
      onTap = () => _openBizPartner(context, _supplier ? 'supplier' : 'channel', _s(partner['id']), name: _s(partner['name']));
      action = '去看$kindLabel ›';
    } else if (parties.isEmpty) {
      text = '规则里没有填写对方主体。';
      color = _kInk2;
      soft = _kPanel;
    } else {
      final bad = parties.where((e) => !same(e)).toList();
      if (bad.isEmpty) {
        text = '规则对方主体与法人主体「${full.isEmpty ? short : full}」一致。';
        color = _kDeep;
        soft = _kLavender;
      } else {
        text = '规则对方主体「${bad.join('、')}」与法人主体「${full.isEmpty ? short : full}」不一致，请确认是否同一法人。';
        color = _kCoral;
        soft = _kCoralSoft;
      }
      onTap = () => _openBizSubject(context, subjectId, short);
      action = '看法人主体 ›';
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
        decoration: BoxDecoration(color: _bg(context, soft), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: _sans(context, size: 11, color: color, height: 1.6)),
            if (action.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(action, style: _sans(context, size: 11, weight: FontWeight.w600, color: _kDeep)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 主体页（合作主体法人档案）──

class LighthouseBizSubjectPage extends StatefulWidget {
  const LighthouseBizSubjectPage({super.key, required this.service, required this.id, this.title = ''});

  final LighthouseService service;
  final String id;
  final String title;

  @override
  State<LighthouseBizSubjectPage> createState() => _BizSubjectState();
}

class _BizSubjectState extends State<LighthouseBizSubjectPage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await widget.service.fetchBizSubject(id: widget.id);
      if (!mounted) return;
      setState(() => _data = d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final children = <Widget>[];
    if (d == null) {
      children.add(_error != null ? _inlineError(context, _error!, _load) : _bizLoading());
    } else {
      final sub = _map(d['subject']);
      final totals = _map(d['totals']);
      final suppliers = _list(d['suppliers']);
      final channels = _list(d['channels']);
      final short = _s(sub['partnerShortName']);
      final full = _s(sub['partnerFullName']);
      final products = _i(totals['products']) ?? 0;
      final settled = _i(totals['settledProducts']) ?? 0;
      final expiring = _i(totals['expiringProducts']) ?? 0;
      final code = [_s(sub['unifiedSocialCreditCode']), _s(sub['socialCreditCode']), _s(sub['creditCode'])].firstWhere((e) => e.isNotEmpty, orElse: () => '');
      final nChannels = _i(totals['channels']) ?? channels.length;
      children
        ..add(_relationChain(context, [
          _ChainSeg('法人主体', short.isEmpty ? (widget.title.isEmpty ? '—' : widget.title) : short, current: true),
          _ChainSeg('供应商', '${_count(_i(totals['suppliers']) ?? suppliers.length)} 家'),
          _ChainSeg('渠道', '${_count(nChannels)} 家', tone: nChannels == 0 ? _SegTone.bad : _SegTone.normal),
          _ChainSeg('结算', '${_count(settled)} 个产品', tone: expiring > 0 ? _SegTone.warn : _SegTone.normal, sub: expiring > 0 ? '$expiring 个快到期' : ''),
        ]))
        ..add(const SizedBox(height: 10))
        ..add(Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDeco(context, radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(full.isEmpty ? (short.isEmpty ? '—' : short) : full, style: _sans(context, size: 14, weight: FontWeight.w700, height: 1.35)),
              const SizedBox(height: 3),
              Text(
                [if (short.isNotEmpty) '简称 $short', if (code.isNotEmpty) '统一社会信用代码 $code'].join(' · '),
                style: _sans(context, size: 10.5, color: _kMute),
              ),
              const SizedBox(height: 12),
              _bizCellGrid(context, [
                ('旗下产品', '${_count(products)} 个'),
                ('审核生效', '${_count(_i(totals['effectiveProducts']))} 个'),
                ('结算覆盖', _pct(settled, products)),
              ]),
            ],
          ),
        ))
        ..add(_bizSection(context, '供应商', count: suppliers.length));
      if (suppliers.isEmpty) {
        children.add(_emptyNote(context, '这个主体下还没有关联供应商。'));
      } else {
        children.add(_bizSpaced([for (final p in suppliers) _bizPartnerCard(context, p)]));
      }
      children.add(_bizSection(context, '渠道', count: channels.length));
      if (channels.isEmpty) {
        children.add(_emptyNote(context, '这个主体下还没有关联渠道。渠道侧关联后，结算规则里的对方主体才能和它对上。'));
      } else {
        children.add(_bizSpaced([for (final p in channels) _bizPartnerCard(context, p)]));
      }
    }
    return _bizSubPage(context, title: '法人主体', onRefresh: _load, children: children);
  }

  Widget _emptyNote(BuildContext context, String text) => Container(
    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
    decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: _sans(context, size: 11, color: _kInk2, height: 1.6)),
  );
}

// ═════════════════════════════ 业务脉搏 · 画法 ═════════════════════════════
//
//   左：链路盘。四圈从外到内 = 渠道产品 / 已连接供给 / 双端生效 / 已配结算，弧长 = 占渠道产品的比例；
//       比上一圈缩得最多的那一圈用蜜桃色。中心是贯通率（已配结算 ÷ 渠道产品）。点某圈 → 产品列表对应分段。
//   右：环形心电。一圈 = 24 小时，0 点在正上方；每 10 分钟一档推送跳一个心搏（条数越多越高），失败向内跳；
//       内圈菱形是结算回传批次；未到的时间是虚线，线头的光点是「现在」。

const _kRingKeys = ['', 'connected', 'usable', _kChainThrough];

/// 上一次拿到的业务总览：切走再回来时先用它画，同时后台刷新。
Map<String, dynamic>? _bizOverviewCache;
const _kRingNames = ['渠道产品', '已连接供给', '双端生效', '已配结算'];
const _kRingGrad = [
  [Color(0xFFE4DFFD), Color(0xFFC9C0F8)],
  [Color(0xFFCBD7FC), Color(0xFF9DB3F6)],
  [Color(0xFFC7D9FB), Color(0xFF8FB6F2)],
  [Color(0xFFB9A6F0), Color(0xFF7B5CD8)],
];
const _kRingDropGrad = [Color(0xFFFBD3C6), Color(0xFFF09B82)];
const _kRingRadii = [0.385, 0.318, 0.25, 0.183];

String _chainLabel(String key) => switch (key) {
  '' => '全部',
  'connected' => '已连接',
  'usable' => '双端生效',
  _kChainThrough => '已配结算',
  _ => _chainSeg(key).$1,
};

Offset _polar(Offset c, double r, double angle) => c + Offset(math.cos(angle), math.sin(angle)) * r;

class _ChainRingDial extends StatefulWidget {
  const _ChainRingDial({required this.values, required this.drop, required this.onPick});

  /// [渠道产品, 已连接供给, 双端生效, 已配结算]；null = 数据还没到，只画刻度和空轨道。
  final List<int>? values;
  final int drop;
  final ValueChanged<String> onPick;

  @override
  State<_ChainRingDial> createState() => _ChainRingDialState();
}

class _ChainRingDialState extends State<_ChainRingDial> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();
  int? _pressed;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChainRingDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 骨架 → 真数据：圆弧从 0 画到位，和资管时钟一样「先出盘、再走针」。
    if (oldWidget.values == null && widget.values != null) {
      unawaited(_intro.forward(from: 0));
    }
  }

  int? _hit(Offset p, double d) {
    final r = (p - Offset(d / 2, d / 2)).distance / d;
    for (var i = 0; i < _kRingRadii.length; i++) {
      if ((r - _kRingRadii[i]).abs() <= 0.034) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.values != null;
    final v = widget.values ?? const [0, 0, 0, 0];
    final through = v[0] <= 0 ? 0.0 : v[3] / v[0];
    final grads = [
      for (var i = 0; i < 4; i++) [for (final c in (i == widget.drop ? _kRingDropGrad : _kRingGrad[i])) _fg(context, c)],
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final d = box.maxWidth;
        return Semantics(
          label: '链路盘：渠道产品 ${v[0]}，已连接供给 ${v[1]}，双端生效 ${v[2]}，已配结算 ${v[3]}，贯通率 ${(through * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => setState(() => _pressed = _hit(e.localPosition, d)),
            onTapCancel: () => setState(() => _pressed = null),
            onTapUp: (e) {
              final i = _hit(e.localPosition, d);
              setState(() => _pressed = null);
              widget.onPick(_kRingKeys[i ?? 0]);
            },
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, child) => CustomPaint(
                painter: _ChainRingPainter(
                  values: v,
                  t: _intro.value,
                  pressed: _pressed,
                  tick: _fg(context, _kDeep),
                  track: _fg(context, _kPurple),
                  grads: grads,
                ),
                child: child,
              ),
              child: SizedBox(
                width: d,
                height: d,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ready ? '${(through * 100).round()}%' : '—',
                        style: LhTypography.mono(context: context, size: 18, weight: FontWeight.w700, color: _fg(context, _kHeroNum)),
                      ),
                      const SizedBox(height: 1),
                      Text('贯通', style: _sans(context, size: 9.5, color: _kMute)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChainRingPainter extends CustomPainter {
  _ChainRingPainter({
    required this.values,
    required this.t,
    required this.pressed,
    required this.tick,
    required this.track,
    required this.grads,
  });

  final List<int> values;
  final double t;
  final int? pressed;
  final Color tick;
  final Color track;
  final List<List<Color>> grads;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = size.center(Offset.zero);
    final stroke = d * 0.042;
    // 外圈刻度：0–100%，每 10% 一根长刻度
    for (var i = 0; i < 50; i++) {
      final a = i / 50 * 2 * math.pi - math.pi / 2;
      final long = i % 5 == 0;
      canvas.drawLine(
        _polar(c, d * 0.468, a),
        _polar(c, d * (long ? 0.44 : 0.452), a),
        Paint()
          ..color = tick.withValues(alpha: long ? 0.35 : 0.14)
          ..strokeWidth = long ? 1 : 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
    final total = values[0];
    for (var i = 0; i < 4; i++) {
      final r = d * _kRingRadii[i];
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track.withValues(alpha: 0.07),
      );
      final p = total <= 0 ? 0.0 : (values[i] / total).clamp(0.0, 1.0).toDouble();
      final local = Curves.easeOutCubic.transform(((t * 1.35) - i * 0.1).clamp(0.0, 1.0).toDouble());
      final sweep = 2 * math.pi * p * local;
      if (sweep <= 0.001) continue;
      final alpha = pressed == null || pressed == i ? 1.0 : 0.25;
      Shader shader(double a) => SweepGradient(
        endAngle: math.max(sweep, 0.01),
        colors: [for (final g in grads[i]) g.withValues(alpha: a)],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2)
          ..shader = shader(0.5 * alpha),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader(alpha),
      );
      if (p < 0.995 && local >= 1) {
        canvas.drawCircle(_polar(c, r, -math.pi / 2 + sweep), stroke * 0.28, Paint()..color = Colors.white.withValues(alpha: alpha));
      }
    }
  }

  @override
  bool shouldRepaint(_ChainRingPainter old) =>
      old.t != t || old.pressed != pressed || old.values != values || old.tick != tick || old.grads != grads;
}

class _PulseDial extends StatefulWidget {
  const _PulseDial({required this.pushes, required this.returns, required this.total, required this.onTap});

  /// (当天分钟数, 条数, 失败数)，10 分钟一档。
  final List<(int, int, int)> pushes;

  /// (当天分钟数, 是否异常)
  final List<(int, bool)> returns;
  final int total;
  final VoidCallback onTap;

  @override
  State<_PulseDial> createState() => _PulseDialState();
}

class _PulseDialState extends State<_PulseDial> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  /// 心跳节拍：约 48 次 / 分，每拍「咚—哒」两下。
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250))..repeat();

  List<Offset> _pts = const [];
  String _cacheKey = '';

  @override
  void didUpdateWidget(covariant _PulseDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 首次拿到当天数据时，心电线从 0 点重新画到现在。
    final wasEmpty = oldWidget.pushes.isEmpty && oldWidget.returns.isEmpty;
    final hasData = widget.pushes.isNotEmpty || widget.returns.isNotEmpty;
    if (wasEmpty && hasData) unawaited(_intro.forward(from: 0));
  }

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    super.dispose();
  }

  static double _hourAngle(double h) => h / 24 * 2 * math.pi - math.pi / 2;

  /// 心电采样点：基线是一条圆，每档推送在档位中点跳一个心搏（只画成功的条数，失败另画）。
  List<Offset> _ecg(double d, double nowH) {
    final key = '${d.toStringAsFixed(1)}|${(nowH * 60).floor()}|${widget.pushes.length}|${widget.returns.length}|${widget.total}';
    if (key == _cacheKey) return _pts;
    final c = Offset(d / 2, d / 2);
    final base = d * 0.29;
    double g(double x, double m, double w) => math.exp(-((x - m) * (x - m)) / (2 * w * w));
    // 推送是大心跳（10 分钟一档，条数越多越高）；结算回传是小心跳（每批一下，异常的另画珊瑚色菱形）。
    final beats = [
      for (final p in widget.pushes)
        if (p.$2 - p.$3 > 0) ((p.$1 + 5) / 60.0, d * math.min(0.12, 0.03 + 0.016 * math.log(1 + (p.$2 - p.$3)))),
    ];
    // 回传一天几百批，逐批叠加会把线顶出表盘；先按 10 分钟合并，再按对数给一个细尖峰。
    final retBuckets = <int, int>{};
    for (final r in widget.returns) {
      if (r.$2) continue; // 异常批次另画珊瑚色菱形
      final m = r.$1 ~/ 10 * 10;
      retBuckets[m] = (retBuckets[m] ?? 0) + 1;
    }
    final smallBeats = [
      for (final e in retBuckets.entries) ((e.key + 5) / 60.0, d * math.min(0.022, 0.008 + 0.005 * math.log(1 + e.value))),
    ];
    final cap = d * 0.415;
    final pts = <Offset>[];
    for (var h = 0.0; h <= nowH; h += 0.01) {
      var r = base;
      // 每个点只取最高的那个心搏，不叠加：同一时段再密也不会越跳越高。
      var bump = 0.0;
      for (final (hc, a) in beats) {
        final x = h - hc;
        if (x.abs() > 0.7) continue;
        bump = math.max(bump, a * (0.07 * g(x, -0.3, 0.07) + g(x, 0, 0.045) - 0.12 * g(x, 0.12, 0.04) + 0.1 * g(x, 0.38, 0.1)));
      }
      for (final (hc, a) in smallBeats) {
        final x = h - hc;
        if (x.abs() > 0.1) continue;
        bump = math.max(bump, a * g(x, 0, 0.022));
      }
      r = math.min(r + bump, cap);
      pts.add(_polar(c, r, _hourAngle(h)));
    }
    _cacheKey = key;
    _pts = pts;
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final d = box.maxWidth;
        final now = DateTime.now();
        final nowH = now.hour + now.minute / 60;
        final pts = _ecg(d, nowH);
        final failed = widget.pushes.fold<int>(0, (a, e) => a + e.$3);
        return Semantics(
          button: true,
          label: '今日推送 ${widget.total} 次，失败 $failed 次，查看对接',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _intro,
                    builder: (context, _) => CustomPaint(
                      painter: _PulsePainter(
                        pts: pts,
                        nowH: nowH,
                        t: Curves.easeInOutCubic.transform(_intro.value),
                        pushes: widget.pushes,
                        returns: widget.returns,
                        tick: _fg(context, _kDeep),
                        lineA: _fg(context, const Color(0xFF8FB6F2)),
                        lineB: _fg(context, _kPurple),
                        coral: _fg(context, const Color(0xFFE58C72)),
                        hot: _fg(context, _kHeroNum),
                        diamond: _fg(context, const Color(0xFFA9BEF8)),
                        disc: _bg(context, Colors.white),
                        discEdge: _bg(context, const Color(0xFFF0ECFE)),
                        label: LhTypography.mono(context: context, size: 8, weight: FontWeight.w600, color: _fg(context, _kMute)),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _breath]),
                    builder: (context, _) => CustomPaint(
                      painter: _PulseNowPainter(
                        at: pts.isEmpty ? null : pts.last,
                        nowH: nowH,
                        visible: _intro.value >= 1,
                        phase: _breath.value,
                        color: _fg(context, _kHeroNum),
                        ring: _bg(context, Colors.white),
                      ),
                    ),
                  ),
                ),
                Center(
                  // 中心数字跟着心跳「咚—哒」轻轻放大。
                  child: AnimatedBuilder(
                    animation: _breath,
                    builder: (context, child) {
                      final ph = _breath.value;
                      final beat = (_PulseNowPainter._g(ph, 0.08, 0.035) + 0.55 * _PulseNowPainter._g(ph, 0.26, 0.035)).clamp(0.0, 1.0).toDouble();
                      return Transform.scale(scale: 1 + 0.03 * beat, child: child);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_count(widget.total), style: LhTypography.mono(context: context, size: 18, weight: FontWeight.w700, color: _fg(context, _kHeroNum))),
                        const SizedBox(height: 1),
                        Text('次推送', style: _sans(context, size: 9.5, color: _kMute)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.pts,
    required this.nowH,
    required this.t,
    required this.pushes,
    required this.returns,
    required this.tick,
    required this.lineA,
    required this.lineB,
    required this.coral,
    required this.hot,
    required this.diamond,
    required this.disc,
    required this.discEdge,
    required this.label,
  });

  final List<Offset> pts;
  final double nowH;
  final double t;
  final List<(int, int, int)> pushes;
  final List<(int, bool)> returns;
  final Color tick;
  final Color lineA;
  final Color lineB;
  final Color coral;
  final Color hot;
  final Color diamond;
  final Color disc;
  final Color discEdge;
  final TextStyle label;

  static double _a(double h) => h / 24 * 2 * math.pi - math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = size.center(Offset.zero);
    final base = d * 0.29;
    // 小时刻度与 0 / 6 / 12 / 18
    for (var h = 0; h < 24; h++) {
      final main = h % 6 == 0;
      canvas.drawLine(
        _polar(c, d * 0.45, _a(h.toDouble())),
        _polar(c, d * (main ? 0.42 : 0.435), _a(h.toDouble())),
        Paint()
          ..color = tick.withValues(alpha: main ? 0.38 : 0.15)
          ..strokeWidth = main ? 1.1 : 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final h in const [0, 6, 12, 18]) {
      final tp = TextPainter(text: TextSpan(text: '$h', style: label), textDirection: TextDirection.ltr)..layout();
      final p = _polar(c, d * 0.49, _a(h.toDouble()));
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    // 表心
    final discR = d * 0.21;
    canvas.drawCircle(
      c,
      discR,
      Paint()..shader = RadialGradient(colors: [disc, discEdge.withValues(alpha: 0.6)]).createShader(Rect.fromCircle(center: c, radius: discR)),
    );
    canvas.drawCircle(c, discR, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = tick.withValues(alpha: 0.08));
    // 未到的时间：虚线基线
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = tick.withValues(alpha: 0.22);
    final rect = Rect.fromCircle(center: c, radius: base);
    for (var h = nowH + 0.15; h < 24; h += 0.32) {
      canvas.drawArc(rect, _a(h), 0.08 / 24 * 2 * math.pi, false, dash);
    }
    // 回传批次：内圈小菱形
    for (final (m, abnormal) in returns) {
      // 正常回传已经画成心电上的小心跳，这里只标异常批次。
      if (!abnormal) continue;
      final p = _polar(c, d * 0.234, _a(m / 60));
      final s = d * 0.016;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 2), Radius.circular(s * 0.3)),
        Paint()..color = abnormal ? coral : diamond,
      );
      canvas.restore();
    }
    if (pts.length < 2) return;
    // 心电：入场时从 0 点画到现在
    final n = math.max(2, (pts.length * t).round());
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    final shader = LinearGradient(colors: [lineA, const Color(0xFF9C84EA), lineB]).createShader(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4)
        ..shader = LinearGradient(colors: [lineA.withValues(alpha: 0.35), lineB.withValues(alpha: 0.35)]).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    // 最近一小时（约 100 个采样点）从主紫渐变到深紫，线头一段更沉、更清楚。
    if (t >= 1) {
      const hot = 100;
      const deep = Color(0xFF3B246E);
      final from = math.max(1, n - hot);
      for (var i = from; i < n; i++) {
        final k = (i - from) / math.max(1, n - from);
        canvas.drawLine(
          pts[i - 1],
          pts[i],
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = Color.lerp(lineB, deep, k)!,
        );
      }
    }
    // 失败：同一时刻向内跳一下，珊瑚色
    final drawnH = nowH * t;
    for (final (m, _, failed) in pushes) {
      if (failed <= 0) continue;
      final hc = (m + 5) / 60;
      if (hc > drawnH) continue;
      final a = d * math.min(0.08, 0.025 + 0.014 * math.log(1 + failed));
      final fp = Path();
      for (var k = -12; k <= 12; k++) {
        final x = k * 0.01;
        final r = base - a * math.exp(-(x * x) / (2 * 0.045 * 0.045));
        final p = _polar(c, r, _a(hc + x));
        if (k == -12) {
          fp.moveTo(p.dx, p.dy);
        } else {
          fp.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        fp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..color = coral,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.t != t || old.pts != pts || old.nowH != nowH || old.tick != tick || old.pushes != pushes;
}

/// 「现在」：线头一直在跳的心跳。每拍「咚—哒」两下：线头向前探出一小段心搏波形，光点随之放大、外圈扩散。
/// 这段只表示「正在监测」，画在未来那一侧，不覆盖今天真实的推送波形。
class _PulseNowPainter extends CustomPainter {
  _PulseNowPainter({required this.at, required this.nowH, required this.visible, required this.phase, required this.color, required this.ring});

  final Offset? at;
  final double nowH;
  final bool visible;
  final double phase;
  final Color color;
  final Color ring;

  static double _g(double x, double m, double w) => math.exp(-((x - m) * (x - m)) / (2 * w * w));

  @override
  void paint(Canvas canvas, Size size) {
    final p = at;
    if (p == null || !visible) return;
    final c = size.center(Offset.zero);
    final d = size.shortestSide;
    final rHead = (p - c).distance;
    // 节拍包络：0.08 处「咚」，0.26 处「哒」
    final beat = (_g(phase, 0.08, 0.035) + 0.55 * _g(phase, 0.26, 0.035)).clamp(0.0, 1.0).toDouble();
    // 线头探出的一小段心搏：0.4 小时宽，R 波朝外
    final tip = Path()..moveTo(p.dx, p.dy);
    for (var i = 1; i <= 24; i++) {
      final x = i / 24;
      final h = nowH + x * 0.4;
      final r = rHead + d * 0.08 * beat * (_g(x, 0.32, 0.07) - 0.35 * _g(x, 0.5, 0.06));
      tip.lineTo(c.dx + r * math.cos(h / 24 * 2 * math.pi - math.pi / 2), c.dy + r * math.sin(h / 24 * 2 * math.pi - math.pi / 2));
    }
    canvas.drawPath(
      tip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.2 + 0.6 * beat),
    );
    // 线头：深紫圆点，外面一圈细环随节拍缓慢扩散，像监护仪的采样点——稳，不闹。
    final halo = (phase / 0.7).clamp(0.0, 1.0).toDouble();
    canvas.drawCircle(
      p,
      4 + 9 * halo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.45 * (1 - halo)),
    );
    final r = 2.6 + 0.6 * beat;
    canvas.drawCircle(p, r + 1.2, Paint()..color = ring);
    canvas.drawCircle(p, r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulseNowPainter old) => old.phase != phase || old.at != at || old.visible != visible || old.nowH != nowH;
}

/// 读数格右侧的小环；value 为 0 时只在起点留一个点，为 null 时只画底环。
class _MiniRingPainter extends CustomPainter {
  _MiniRingPainter({required this.value, required this.color});

  final double? value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.8..color = color.withValues(alpha: 0.16));
    final v = value;
    if (v == null) return;
    if (v <= 0) {
      canvas.drawCircle(_polar(c, r, -math.pi / 2), 1.8, Paint()..color = color);
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_MiniRingPainter old) => old.value != value || old.color != color;
}

/// 标题旁的实时小点：1.6 秒一次呼吸。
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5 * (1 - _c.value)), spreadRadius: 6 * _c.value)],
        ),
      ),
    );
  }
}

// ═════════════════════════════ 关联：关系链与互链 ═════════════════════════════
//
//   列表卡片底部是「迷你关系链」，详情页顶部是同一组件的完整版：合作主体 › 渠道 / 供应商 › 产品 › 结算。
//   卡片 / 页面自己那一节不出现在迷你链上；详情页里当前节点高亮。每一节都能点，跳到对应详情：
//     合作主体 → 主体页（/subject）  渠道 / 供应商 → 合作主体详情（/partner）
//     产品 → 产品详情（/product）     结算 → 结算详情（/settlement）
//   颜色：珊瑚 = 断了（未关联、未连接、对不上）；铜 = 要注意（待审核、快到期）；灰 = 还没有。

enum _SegTone { normal, warn, bad, none }

class _ChainSeg {
  const _ChainSeg(this.label, this.value, {this.sub = '', this.tone = _SegTone.normal, this.onTap, this.current = false});

  final String label;
  final String value;
  final String sub;
  final _SegTone tone;
  final VoidCallback? onTap;
  final bool current;
}

Color _segColor(_SegTone t) => switch (t) {
  _SegTone.bad => _kCoral,
  _SegTone.warn => _kCopper,
  _SegTone.none => const Color(0xFFAAA8B3),
  _SegTone.normal => _kInk,
};

Widget _segBody(BuildContext context, _ChainSeg s, {double valueSize = 11.5}) {
  final dot = switch (s.tone) {
    _SegTone.bad => _kCoral,
    _SegTone.warn => const Color(0xFFD9A24F),
    _ => s.current ? _kPurple : null,
  };
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (dot != null) ...[
            Container(width: 5, height: 5, decoration: BoxDecoration(color: _fg(context, dot), shape: BoxShape.circle)),
            const SizedBox(width: 3),
          ],
          Flexible(child: Text(s.label, maxLines: 1, overflow: TextOverflow.clip, style: _sans(context, size: 9.5, color: _kMute))),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        s.value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _sans(context, size: valueSize, weight: s.tone == _SegTone.none ? FontWeight.w500 : FontWeight.w600, color: s.current ? _kDeep : _segColor(s.tone)),
      ),
      const SizedBox(height: 1),
      Text(s.sub.isEmpty ? ' ' : s.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 9.5, color: _kMute)),
    ],
  );
}

Widget _segArrow(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 1),
  child: Text('›', style: _sans(context, size: 12, color: const Color(0xFFC9BCF3))),
);

Widget _segTap(BuildContext context, _ChainSeg s, Widget child) {
  final onTap = s.onTap;
  if (onTap == null || s.current) return child;
  return Semantics(
    button: true,
    label: '${s.label} ${s.value}',
    excludeSemantics: true,
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
  );
}

/// 列表卡片底部的迷你关系链。
Widget _miniChain(BuildContext context, List<_ChainSeg> segs) {
  return Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        for (var i = 0; i < segs.length; i++) ...[
          if (i > 0) _segArrow(context),
          Expanded(
            child: _segTap(
              context,
              segs[i],
              Padding(padding: const EdgeInsets.fromLTRB(7, 5, 6, 6), child: _segBody(context, segs[i])),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 详情页顶部的关系链：当前节点高亮，其余可点。
Widget _relationChain(BuildContext context, List<_ChainSeg> segs) {
  return Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: _bg(context, Colors.white),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _ln(context, _kEdge), width: 0.8),
    ),
    child: Row(
      children: [
        for (var i = 0; i < segs.length; i++) ...[
          if (i > 0) _segArrow(context),
          Expanded(
            child: _segTap(
              context,
              segs[i],
              Container(
                padding: const EdgeInsets.fromLTRB(7, 5, 6, 6),
                decoration: segs[i].current
                    ? BoxDecoration(
                        gradient: LinearGradient(colors: [_bg(context, const Color(0xFFF2EEFE)), _bg(context, const Color(0xFFEAF1FD))]),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                child: _segBody(context, segs[i], valueSize: 11),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 链下面的一句话说明（只在有问题时出现）。
Widget _chainHint(BuildContext context, String text, Color color) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Row(
    children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: _fg(context, color), shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: color))),
      const SizedBox(width: 6),
      Text('详情 ›', style: _sans(context, size: 10.5, color: _kMute)),
    ],
  ),
);

// ── 跳转 ──

void _openBizProduct(BuildContext context, String side, String id, String name) {
  if (id.isEmpty) return;
  Navigator.of(context).pushNamed('/product', arguments: {'side': side, 'id': id, 'name': name});
}

void _openBizPartner(BuildContext context, String kind, String id, {String name = '', Map<String, dynamic>? data, String tab = ''}) {
  if (id.isEmpty) return;
  Navigator.of(context).pushNamed('/partner', arguments: {'kind': kind, 'id': id, 'name': name, 'data': data, 'tab': tab});
}

void _openBizSettlement(BuildContext context, String side, String id, String name) {
  if (id.isEmpty) return;
  Navigator.of(context).pushNamed('/settlement', arguments: {'side': side, 'id': id, 'name': name});
}

void _openBizSubject(BuildContext context, String id, String name) {
  if (id.isEmpty || id == '0') return;
  Navigator.of(context).pushNamed('/subject', arguments: {'id': id, 'name': name});
}

// ── 小工具 ──

/// 距今天还有几天到期；空 / 解析失败 → null。
int? _daysUntil(Object? v) {
  final s = _s(v);
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  if (d == null) return null;
  final now = DateTime.now();
  return d.difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// 「至 12-31」/「长期」。
String _expireShort(Object? v) {
  final s = _s(v);
  return s.length >= 10 ? '至 ${s.substring(5, 10)}' : '长期';
}

/// 首条结算规则摘要：比例 0.985 / 单价 ¥0.20 / ¥10.00 × 0.98。
String _ruleShort(String code, Object? ratio, Object? unitPrice, String label) => switch (code) {
  '1' => '比例 ${_plain(ratio)}',
  '2' => '单价 ${_yuan(unitPrice)}',
  '5' => '${_yuan(unitPrice)} × ${_plain(ratio)}',
  _ => label,
};

String _spStateLabel(String v) => switch (v) {
  'effective' => '供应商产品 生效',
  'pending' => '供应商产品 待审核',
  'disabled' => '供应商产品 已停用',
  _ => '',
};

/// 结算段：条数 + 方式 + 到期；30 天内到期标铜色。
_ChainSeg _settleSeg(BuildContext context, Map<String, dynamic> p, String side, {bool usable = true}) {
  final n = _i(p['settlementCount']) ?? 0;
  final days = _daysUntil(p['settlementExpire']);
  final soon = days != null && days <= 30;
  final rule = _ruleShort(_s(p['settleMethodCode']), p['settlementRatio'], p['settlementUnitPrice'], _s(p['settleMethod']));
  return _ChainSeg(
    '结算',
    n > 0 ? '$n 条' : '未配置',
    sub: n > 0 ? [if (rule.isNotEmpty) rule, soon ? '$days 天到期' : _expireShort(p['settlementExpire'])].join(' · ') : (usable ? '双端已生效' : ''),
    tone: n > 0 ? (soon ? _SegTone.warn : _SegTone.normal) : (usable ? _SegTone.bad : _SegTone.none),
    onTap: () => _openBizSettlement(context, side, _s(p['id']), _s(p['name'])),
  );
}

// ═════════════════════════════ 列表卡片（首页、合作主体详情、主体页共用） ═════════════════════════════

/// 合作主体卡：名称 / 归属 + 迷你链（合作主体 › 产品 › 结算）。推广商没有产品，沿用规则读数。
Widget _bizPartnerCard(BuildContext context, Map<String, dynamic> p) {
  final name = _s(p['name']).isEmpty ? '—' : _s(p['name']);
  final (statusLabel, tone) = _partnerStatus(_s(p['status']));
  final kind = _s(p['kind']);
  final kindLabel = switch (kind) {
    'channel' => '渠道',
    'promoter' => '推广商',
    _ => '供应商',
  };
  final sub = _s(p['sub']).isNotEmpty ? _s(p['sub']) : _s(p['shortName']);
  final id = _s(p['id']);
  Widget body;
  String? hint;
  if (kind == 'promoter') {
    final total = _i(p['ruleCount']) ?? 0;
    final active = _i(p['activeRuleCount']) ?? 0;
    body = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _bizCellGrid(context, [
        ('启用规则', '${_count(active)} 条'),
        ('未启用规则', '${_count(total > active ? total - active : 0)} 条'),
        ('规则启用率', _pct(active, total)),
      ]),
    );
  } else {
    final linked = p['subjectLinked'] == true;
    final products = _i(p['productCount']) ?? 0;
    final effective = _i(p['effectiveProductCount']) ?? 0;
    // 统计失败时后端给 null：写「—」，不当成 0。
    final settledN = _i(p['settledProducts']);
    final settled = settledN ?? 0;
    final expiring = _i(p['expiringProducts']) ?? 0;
    final extra = kind == 'channel'
        ? (p['throughProducts'] == null ? '' : ' · 贯通 ${_count(_i(p['throughProducts']))}')
        : (p['usedProducts'] == null ? '' : ' · 被采用 ${_count(_i(p['usedProducts']))}');
    body = _miniChain(context, [
      _ChainSeg(
        '法人主体',
        linked ? (_s(p['subjectName']).isEmpty ? '主体档案不可用' : _subjectDisplay(p['subjectName'])) : '未关联',
        sub: kind == 'channel' && _s(p['entityName']).isNotEmpty ? '签约 ${_s(p['entityName'])}' : '',
        tone: linked ? _SegTone.normal : _SegTone.bad,
        onTap: linked ? () => _openBizSubject(context, _s(p['subjectId']), _s(p['subjectName'])) : null,
      ),
      _ChainSeg(
        '产品',
        '${_count(products)} 个',
        sub: '生效 ${_count(effective)}$extra',
        onTap: () => _openBizPartner(context, kind, id, name: name, data: p, tab: 'product'),
      ),
      _ChainSeg(
        '结算',
        settledN == null ? '—' : '${_count(settled)} 个产品',
        sub: settledN == null ? '' : '覆盖 ${_pct(settled, products)}${expiring > 0 ? ' · $expiring 个快到期' : ''}',
        tone: settledN == null
            ? _SegTone.none
            : (expiring > 0 ? _SegTone.warn : (settled == 0 && products > 0 ? _SegTone.none : _SegTone.normal)),
        onTap: () => _openBizPartner(context, kind, id, name: name, data: p, tab: 'settle'),
      ),
    ]);
    if (!linked) hint = '$kindLabel未关联法人主体，结算规则无法核对对方是否同一法人';
  }
  return _tapCard(
    context,
    label: '$name，查看详情',
    onTap: () => _openBizPartner(context, kind, id, name: name, data: p),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _bg(context, _kLavender), borderRadius: BorderRadius.circular(10)),
              child: Text(name.characters.first, style: _sans(context, size: 13.5, weight: FontWeight.w700, color: _kDeep)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 13.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [kindLabel, if (sub.isNotEmpty) sub].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(context, size: 10.5, color: _kMute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _tag(context, statusLabel, tone),
          ],
        ),
        body,
        if (hint != null) _chainHint(context, hint, _kCoral),
      ],
    ),
  );
}

/// 结算卡：产品名 / 首条规则 + 迷你链（合作主体 › 渠道或供应商 › 产品）；点卡片进结算详情。
Widget _bizSettlementCard(BuildContext context, Map<String, dynamic> p, int index, {required String fallbackSide}) {
  final side = _s(p['side']).isEmpty ? fallbackSide : _s(p['side']);
  final name = _s(p['name']).isEmpty ? '—' : _s(p['name']);
  final n = _i(p['settlementCount']) ?? 0;
  final days = _daysUntil(p['settlementExpire']);
  final soon = n > 0 && days != null && days <= 30;
  final rule = _ruleShort(_s(p['settleMethodCode']), p['settlementRatio'], p['settlementUnitPrice'], _s(p['settleMethod']));
  final sub = n == 0
      ? '还没有结算规则'
      : [if (_s(p['settlementBillType']).isNotEmpty) _s(p['settlementBillType']), if (rule.isNotEmpty) rule, if (n > 1) '另 ${n - 1} 条'].join(' · ');
  final match = _s(p['counterpartyMatch']);
  final partnerKind = side == 'supplier' ? 'supplier' : 'channel';
  final partnerLabel = side == 'supplier' ? '供应商' : '渠道';
  final subjectName = _s(p['partnerSubjectName']);
  final our = _s(p['settlementOurEntity']);
  final (matchText, matchTone) = switch (match) {
    'match' => ('主体一致', _SegTone.normal),
    'mismatch' => ('对方主体不一致', _SegTone.bad),
    'unlinked' => ('未关联主体', _SegTone.warn),
    _ => ('', _SegTone.normal),
  };
  final _ChainSeg productSeg;
  if (side == 'channel' && p['chainKnown'] == true) {
    final brk = _i(p['chainBreak']) ?? -1;
    final seg = _chainSegOfBreak(brk);
    productSeg = _ChainSeg(
      '产品',
      brk < 0 ? '已贯通' : _chainSeg(seg).$1,
      sub: _s(p['chainSupplier']).isEmpty ? '' : '供应 ${_s(p['chainSupplier'])}',
      tone: brk < 0 ? _SegTone.normal : (seg == 'unconnected' ? _SegTone.none : (seg == 'half' ? _SegTone.bad : _SegTone.warn)),
      onTap: () => _openBizProduct(context, side, _s(p['id']), name),
    );
  } else {
    final (label, tone) = _submitStatus(_s(p['submitStatus']));
    productSeg = _ChainSeg(
      '产品',
      label,
      sub: _productStatus(side, _s(p['status'])),
      tone: tone == _Tone.purple ? _SegTone.normal : _SegTone.warn,
      onTap: () => _openBizProduct(context, side, _s(p['id']), name),
    );
  }
  String? hint;
  Color hintColor = _kCopper;
  if (match == 'mismatch') {
    hint = '规则对方主体「${_s(p['settlementCounterparty'])}」与法人主体「$subjectName」不一致';
    hintColor = _kCoral;
  } else if (soon) {
    hint = (days ?? 0) <= 0 ? '今天到期，续签前请确认新规则' : '$days 天后到期，续签前请确认新规则';
  } else if (n == 0) {
    hint = '这个产品还没有结算规则';
    hintColor = _kChainGrey;
  }
  return _tapCard(
    context,
    label: '$name，结算 $n 条，查看结算详情',
    onTap: () => _openBizSettlement(context, side, _s(p['id']), name),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: _bizIndexBadge(context, index.toString().padLeft(2, '0'))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: _sans(context, size: 13.5, weight: FontWeight.w700, height: 1.3)),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 10.5, color: _kMute)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(n == 0 ? '—' : _expireShort(p['settlementExpire']), style: _sans(context, size: 10, color: _kMute)),
                const SizedBox(height: 4),
                n == 0
                    ? _tag(context, '未配置', _Tone.grey)
                    : (soon ? _tag(context, (days ?? 0) <= 0 ? '今天到期' : '$days 天到期', _Tone.copper) : _tag(context, '生效中', _Tone.purple)),
              ],
            ),
          ],
        ),
        _miniChain(context, [
          _ChainSeg(
            '法人主体',
            subjectName.isEmpty ? '未关联' : _subjectDisplay(subjectName),
            sub: our.isEmpty ? '' : '我方 ${_subjectDisplay(our)}',
            tone: subjectName.isEmpty ? _SegTone.warn : _SegTone.normal,
            onTap: _s(p['partnerSubjectId']).isEmpty ? null : () => _openBizSubject(context, _s(p['partnerSubjectId']), subjectName),
          ),
          _ChainSeg(
            partnerLabel,
            _s(p['partner']).isEmpty ? '—' : _s(p['partner']),
            sub: matchText,
            tone: matchTone,
            onTap: () => _openBizPartner(context, partnerKind, _s(p['partnerId']), name: _s(p['partner'])),
          ),
          productSeg,
        ]),
        if (hint != null) _chainHint(context, hint, hintColor),
      ],
    ),
  );
}

/// 产品卡的迷你链（渠道产品：合作主体 › 供应商 › 结算；供应商产品：合作主体 › 供应商 › 结算）与问题提示。
(List<_ChainSeg>, String?, Color) _productChain(BuildContext context, Map<String, dynamic> p, String side) {
  final subject = _s(p['chainSubject']);
  final subjectId = _s(p['chainSubjectId']);
  final supplier = _s(p['chainSupplier']);
  final supplierId = _s(p['chainSupplierId']);
  final name = _s(p['name']);
  if (side == 'supplier') {
    final used = _i(p['usedBy']) ?? 0;
    final n = _i(p['settlementCount']) ?? 0;
    final days = _daysUntil(p['settlementExpire']);
    final segs = [
      _ChainSeg(
        '法人主体',
        subject.isEmpty ? '未关联' : _subjectDisplay(subject),
        tone: subject.isEmpty ? _SegTone.warn : _SegTone.normal,
        onTap: subjectId.isEmpty ? null : () => _openBizSubject(context, subjectId, subject),
      ),
      _ChainSeg(
        '供应商',
        supplier.isEmpty ? '—' : supplier,
        sub: used > 0 ? '被 $used 个渠道产品采用' : '还没有渠道采用',
        tone: used > 0 ? _SegTone.normal : _SegTone.none,
        onTap: () => _openBizPartner(context, 'supplier', supplierId, name: supplier),
      ),
      _settleSeg(context, p, side, usable: false),
    ];
    String? hint;
    var color = _kCopper;
    if (n == 0) {
      hint = '供应商侧还没有结算规则';
      color = _kChainGrey;
    } else if (days != null && days <= 30) {
      hint = '结算规则 $days 天后到期';
    }
    return (segs, hint, color);
  }
  if (p['chainKnown'] != true) {
    // 链路没算出来（接口降级）时三格都写「—」，不能默认成已贯通。
    return (
      [
        const _ChainSeg('法人主体', '—', tone: _SegTone.none),
        const _ChainSeg('供应商', '—', tone: _SegTone.none),
        _settleSeg(context, p, 'channel', usable: false),
      ],
      null,
      _kInk,
    );
  }
  final brk = _i(p['chainBreak']) ?? -1;
  final spState = _s(p['supplierProductState']);
  final reason = _s(p['chainReason']);
  final segs = [
    _ChainSeg(
      '法人主体',
      brk == 0 ? '—' : (subject.isEmpty ? '未关联' : _subjectDisplay(subject)),
      tone: brk == 0 ? _SegTone.none : (subject.isEmpty ? _SegTone.warn : _SegTone.normal),
      onTap: subjectId.isEmpty ? null : () => _openBizSubject(context, subjectId, subject),
    ),
    _ChainSeg(
      '供应商',
      brk == 0 ? '未连接' : (supplier.isEmpty ? '—' : supplier),
      sub: brk == 0 ? '没有货源' : (brk == 1 ? '货源已失效' : _spStateLabel(spState)),
      tone: brk <= 1 && brk >= 0 ? _SegTone.bad : (brk == 2 && reason == 'supplierNotEffective' ? _SegTone.warn : _SegTone.normal),
      onTap: supplierId.isEmpty ? null : () => _openBizPartner(context, 'supplier', supplierId, name: supplier),
    ),
    _settleSeg(context, p, 'channel', usable: brk < 0 || brk == 3),
  ];
  final (segName, _, _) = _chainSeg(_chainSegOfBreak(brk));
  // 直接说卡在哪一侧、差什么，不用「一端未生效」这类内部说法。
  final why = switch (reason) {
    'noSource' => '未连接货源：还没有配置供应商产品',
    'sourceBroken' => '货源失效：指向的供应商产品已删除',
    'channelPending' => '卡在渠道侧：渠道产品${_submitStatus(_s(p['submitStatus'])).$1}',
    'channelDisabled' => '卡在渠道侧：渠道产品${_productStatus('channel', _s(p['status']))}',
    'supplierNotEffective' => spState == 'disabled' ? '卡在供应商侧：供应商产品已停用' : '卡在供应商侧：供应商产品待审核',
    'noSettlement' => '未配结算：两端都已生效，还差结算规则',
    _ => segName,
  };
  if (brk >= 0) {
    // 颜色按灯塔的状态语言：铜 = 进行中，灰 = 停用 / 还没有，珊瑚 = 坏了。
    // 「待审核」是正常流程中的状态，链上那一格已经用铜色写了，这里不再重复、也不标红。
    final pending = reason == 'channelPending' || (reason == 'supplierNotEffective' && spState != 'disabled');
    if (pending) return (segs, null, _kInk);
    final color = switch (reason) {
      'sourceBroken' => _kCoral,
      'noSettlement' => _kCopper,
      _ => _kChainGrey,
    };
    return (segs, why, color);
  }
  final days = _daysUntil(p['settlementExpire']);
  if (days != null && days <= 30) return (segs, '已贯通，结算规则 $days 天后到期', _kCopper);
  return (segs, null, _kInk);
}
