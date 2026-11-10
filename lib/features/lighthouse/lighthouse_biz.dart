import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_main_tab_bar.dart';
import 'lighthouse_discount_strip.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';
import 'lighthouse_visibility_sheet.dart';

part 'lighthouse_biz_tier.dart';

// ════════════════════════════════════════════════════════════════════════
// 灯塔 › 业务（2026-11-06）
//
//   灯塔顶部「灯塔 | 资管 | 业务」的第三格：业务平台（资管业务库）的只读视图。
//     · 上面「业务脉搏」：四格分段 + 横滑（阶梯 / 跨档进度 / 推送 / 到期），一屏一图，见文末「业务脉搏 · 方案 A」；
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
// 灯塔 Hero 同款（native_lighthouse_page _LhPlum.heroFill / heroEdge / heroPanelEdge）。
const _kHeroFill = Color(0xFFF7F3FC);
const _kHeroEdge = Color(0xFFE2D8F0);
const _kHeroPanelEdge = Color(0xFFEAE6F1);
const _kHeroMute = Color(0xFF6E6890);
// 四个视角的颜色，取自灯塔 Hero 六段色：核销紫 / 深紫 / 销售蓝 / 收入暖金。
const _kLensColors = [Color(0xFF7054C5), Color(0xFF5A458F), Color(0xFF5488DD), Color(0xFFC88E52)];


// ───────────── 业务链路口径（与 business-go chainScope 一一对应） ─────────────
//   以渠道产品为单位逐层嵌套：渠道产品 ⊇ 已连接供给 ⊇ 双端可售 ⊇ 已配结算。
//   四个互斥分段：已贯通 / 未连接供给 / 未双端可售 / 未配结算，合起来正好是全部渠道产品。
const _kChainThrough = 'through';
const _kChainLeakKeys = ['unconnected', 'half', 'unsettled'];

/// 分段 → (名称, 主色, 浅底)。颜色与总览流向图的分支一致。
(String, Color, Color) _chainSeg(String key) => switch (key) {
  _kChainThrough => ('已贯通', _kHeroNum, _kLavender),
  'unconnected' => ('未连接供给', _kChainGrey, _kGreySoft),
  'half' => ('未双端可售', _kCoral, _kCoralSoft),
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

// ───────────── 主体：谁的主体、没关联时怎么补 ─────────────
//   「主体」在不同页面指的是不同的公司，所以一律写清是谁的：
//     · 供应商主体 = 供应商档案关联的合作主体（产品卡、供应商卡）；
//     · 渠道主体   = 渠道档案关联的合作主体（渠道卡、渠道产品的结算页），对应结算规则里的「对方」；
//     · 我方签约   = 渠道档案 entity_name / 规则 our_entity（广州亿力、上海卓悦…），是我们自己的公司。
//   档案没关联时不当成断点标红：结算明细里本来就有对方公司，后端按名称去主体档案里找同名主体给出建议。

String _legalLabel(String kind) => kind == 'channel' ? '渠道主体' : '供应商主体';

/// 结算对方里档案已有同名主体的那几家（后端 counterparties，已按规则条数倒序）。
List<Map<String, dynamic>> _suggestedSubjects(Object? counterparties) =>
    _list(counterparties).where((c) => _s(c['subjectId']).isNotEmpty).toList();

/// 未关联主体时链格里写什么：有同名档案 → 「待补 · 可关联」，否则「待补」。
String _unlinkedValue(Object? counterparties) => _suggestedSubjects(counterparties).isNotEmpty ? '待补 · 可关联' : '待补';

/// 未关联主体时的一句话：直接给出建议关联谁，没有建议时说清影响。
String _unlinkedHint(String legal, Object? counterparties) {
  final all = _list(counterparties);
  final sug = _suggestedSubjects(counterparties);
  if (sug.isNotEmpty) {
    final first = _subjectDisplay(sug.first['subjectName']);
    return '$legal待补：结算对方「$first」${sug.length > 1 ? '等 ${sug.length} 家' : ''}已有主体档案，可直接关联';
  }
  if (all.isNotEmpty) return '$legal待补：结算对方「${_s(all.first['name'])}」还没有主体档案';
  return '$legal待补：关联后才能核对结算对方是不是同一家公司';
}

/// 结算对方汇总：每家对方公司 · 规则条数 · 档案里的同名主体（可点进主体页）。
Widget _counterpartyList(BuildContext context, Object? counterparties) {
  final all = _list(counterparties);
  if (all.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final c in all)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _s(c['subjectId']).isEmpty ? null : () => _openBizSubject(context, _s(c['subjectId']), _s(c['subjectName'])),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_s(c['name']), style: _sans(context, size: 12, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        _s(c['subjectId']).isEmpty ? '主体档案里没有同名主体，需先在资管建档' : '档案已有：${_subjectDisplay(c['subjectName'])} · 待确认',
                        style: _sans(context, size: 10.5, color: _s(c['subjectId']).isEmpty ? _kMute : _kDeep),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_count(_i(c['rules']))} 条规则', style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kMute))),
                if (_s(c['subjectId']).isNotEmpty) Icon(Icons.chevron_right_rounded, size: 15, color: _fg(context, _kDeep)),
              ],
            ),
          ),
        ),
    ],
  );
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
  'EFFECTIVE' => ('已审核', _Tone.purple),
  'PENDING_AUDIT' => ('待审核', _Tone.copper),
  '' => ('—', _Tone.grey),
  _ => ('未配置', _Tone.grey),
};

/// 渠道产品状态是字符串，供应商产品是 1 / 0。
String _productStatus(String side, String v) {
  if (side == 'supplier') return v == '1' ? '启用' : (v == '0' ? '停用' : (v.isEmpty ? '—' : v));
  return switch (v) {
    'active' => '启用',
    'pending' => '待启用',
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
    this.onOpenLighthouseSupply,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final LighthouseService service;
  final AuthSession session;

  /// 业务 → 灯塔：打开灯塔供给方（行名 + 中石油 / 中石化）。宿主不给就不出现跳转入口。
  final void Function(String province, String group)? onOpenLighthouseSupply;

  @override
  Widget build(BuildContext context) {
    return LhBizLinks(
      openSupply: onOpenLighthouseSupply,
      child: Navigator(
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
        if (settings.name == '/tier') {
          return CupertinoPageRoute<void>(
            settings: settings,
            builder: (_) => LighthouseBizTierPage(service: service, ruleId: _s(args['ruleId'])),
          );
        }
        if (settings.name == '/settlement') {
          return CupertinoPageRoute<void>(
            settings: settings,
            builder: (_) => LighthouseBizProductPage(service: service, side: _s(args['side']), id: _s(args['id']), title: _s(args['name'])),
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
      ),
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
  String _productSide = 'supplier';
  String _partnerKind = 'channel';
  String _subjectFilter = '';
  String _settleSide = 'channel';
  String _settleConfigured = '';
  final Map<_BizTab, String> _priceTypes = {_BizTab.product: 'tiered'};
  String get _priceType => _priceTypes[_tab] ?? '';
  String _chain = '';
  Map<String, dynamic>? _chainCounts;
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
        priceType: _priceType,
        keyword: _keyword,
        syncSource: _platform,
        chain: _productSide == 'channel' ? _chain : '',
        page: page,
        size: _pageSize,
      ),
      _BizTab.partner => s.fetchBizPartners(kind: _partnerKind, priceType: _partnerKind == 'promoter' ? '' : _priceType, keyword: _keyword, subject: _partnerKind != 'promoter' ? _subjectFilter : '', page: page, size: _pageSize),
      _BizTab.settlement => s.fetchBizSettlements(side: _settleSide, priceType: _priceType, configured: _settleConfigured, keyword: _keyword, page: page, size: _pageSize),
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
    // 2026-11-10 · 灯塔风格：整页唯一一块有色面 = 这张 Hero（雾紫底 + 轻紫描边），
    // 里面白色主图区 + 底部三组指标格，与灯塔「本期合计」Hero 同一套层级。
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _bg(context, _kHeroFill),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ln(context, _kHeroEdge), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _bg(context, Colors.white),
                  border: Border.all(color: _ln(context, _kHeroPanelEdge), width: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.monitor_heart_outlined, size: 16, color: _fg(context, _kDeep)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('业务脉搏', style: _sans(context, size: 13.5, weight: FontWeight.w700, color: _kHeroNum)),
                    const SizedBox(height: 2),
                    Text(
                      '阶梯 · 推送 · 结算',
                      style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w500, color: _fg(context, _kHeroMute), letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
              if (synced.length >= 16) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 9, 3),
                  decoration: BoxDecoration(
                    color: _bg(context, Colors.white),
                    border: Border.all(color: _ln(context, _kHeroPanelEdge), width: 0.8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LiveDot(color: _fg(context, _kPurple)),
                      const SizedBox(width: 5),
                      Text('同步于 ${synced.substring(11, 16)}', style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kDeep))),
                    ],
                  ),
                ),
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
            // 数据没到也先出分段和骨架，到了再画图。
            _BizPulseHero(
              service: widget.service,
              overview: o ?? const <String, dynamic>{},
              loading: o == null,
              onOpenPush: _openPushLog,
              onOpenExpiring: _openExpiringSettlements,
            ),
        ],
      ),
    );
  }

  void _resetSearch() {
    _keyword = '';
    _searching = false;
    _searchCtl.clear();
  }

  /// 脉搏「到期」页 → 结算列表「30 天内到期」，与点阵同口径。
  void _openExpiringSettlements() {
    setState(() {
      _tab = _BizTab.settlement;
      _settleSide = 'channel';
      _settleConfigured = 'expiring';
      _priceTypes.remove(_BizTab.settlement);
      _resetSearch();
    });
    unawaited(_loadList());
  }

  /// 脉搏「推送」页 → 对接 › 推送日志。
  void _openPushLog() {
    setState(() {
      _tab = _BizTab.link;
      _linkView = 'push';
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
          if (_tab == _BizTab.product || _tab == _BizTab.settlement || (_tab == _BizTab.partner && _partnerKind != 'promoter')) ...[
            const SizedBox(height: 8),
            _priceFilter(context),
          ],
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
    const tabs = [(_BizTab.product, 'supplier', '供应商产品'), (_BizTab.product, 'channel', '渠道产品与结算'), (_BizTab.partner, '', '合作主体'), (_BizTab.proposal, '', '提案落地'), (_BizTab.link, '', '对接')];
    bool selected(_BizTab tab, String side) => tab == _BizTab.product
        ? (_tab == _BizTab.product && _productSide == side || _tab == _BizTab.settlement && _settleSide == side)
        : _tab == tab;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _ln(context, _kLine), width: 0.8))),
      child: Row(
        children: [
          for (final (tab, side, label) in tabs)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected(tab, side),
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (tab != _BizTab.product) { _switchTab(tab); return; }
                    if (_tab == tab && _productSide == side) return;
                    setState(() {
                      _tab = tab;
                      _productSide = side;
                      _chain = '';
                      _chainCounts = null;
                      _resetSearch();
                    });
                    unawaited(_loadList());
                  },
                  child: SizedBox(
                    height: 44,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: _sans(
                            context,
                            size: MediaQuery.sizeOf(context).width < 600 ? 11.5 : 13,
                            weight: selected(tab, side) ? FontWeight.w700 : FontWeight.w500,
                            color: selected(tab, side) ? _kInk : _kMute,
                          ),
                        ),
                        const SizedBox(height: 7),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: selected(tab, side) ? 20 : 0,
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

  Widget _priceFilter(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final (value, label) in const [('', '全部价格'), ('tiered', '阶梯价格'), ('fixed', '固定价格')]) ...[
        if (value.isNotEmpty) const SizedBox(width: 6),
        _chip(context, label, _priceType == value, () {
          if (_priceType == value) return;
          setState(() {
            _priceTypes[_tab] = value;
            if (_tab == _BizTab.product) _chainCounts = null;
          });
          unawaited(_loadList());
        }),
      ],
    ]),
  );

  Widget _filterRow(BuildContext context) {
    void pick(VoidCallback change) {
      setState(change);
      unawaited(_loadList());
    }

    final chips = <Widget>[
      ...switch (_tab) {
        _BizTab.product => [
          _chip(context, '全部平台', _platform.isEmpty, () => pick(() { _platform = ''; _chainCounts = null; })),
          for (final p in _list(_overview?['platforms']))
            if (_s(p['code']).isNotEmpty)
              _chip(context, _s(p['name']).isEmpty ? _s(p['code']) : _s(p['name']), _platform == _s(p['code']), () => pick(() { _platform = _s(p['code']); _chainCounts = null; })),
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

  /// 与链路盘四圈一一对应的累积筛选：全部 / 已连接 / 双端可售 / 已配结算。
  /// 从底部结论进入的「缺口」分段（未连接供给 / 未双端可售 / 未配结算）以一个可关闭的标签显示。
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
        parts.add(eff == chTotal + spTotal ? '全部已审核' : '已审核 $eff${pend > 0 ? ' · 待审核 $pend' : ''}');
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
              _supplier ? '供应商产品与结算' : '渠道产品与结算',
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
              showValue: double.tryParse(_s(c['cost'])) != null,
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
                      _s(src[i]['subjectName']).isEmpty ? '供应商主体待补' : '供应商主体 ${_subjectDisplay(src[i]['subjectName'])}',
                      switch (_s(src[i]['state'])) {
                        'effective' => '可供货',
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
    final tierRules = _list(d['tierRules']);
    final rules = _list(d['priceRules']);
    final hasTieredSettlement = items.any((it) => _s(it['settleMethod']) == '3');
    final otherRules = tierRules.where((r) => !hasTieredSettlement || !_isSettlementPriceSource(r)).toList();
    out.add(_card(context, '结算规则 · ${_supplier ? '供应商侧' : '渠道侧'} · ${items.length} 条', [
      if (items.isEmpty) _emptyLine(context, '还没有结算规则'),
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Divider(height: 24, thickness: 0.6, color: _ln(context, _kLine)),
        ..._settlementRows(context, items[i]),
        if (_s(items[i]['settleMethod']) == '3') _tierPriceInline(context, items[i], tierRules),
      ],
      if (otherRules.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('其他关联价格配置', style: _sans(context, size: 12, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('采购侧、参与核算或其他关联规则，按各自标注的用途展示。', style: _sans(context, size: 11, color: _kMute)),
        const SizedBox(height: 8),
        _bizSpaced([for (final r in otherRules) _tierRuleCard(context, r)]),
      ] else if (tierRules.isEmpty && rules.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('关联价格配置', style: _sans(context, size: 12, weight: FontWeight.w600)),
        for (final r in rules)
          _kv(context, _s(r['ruleName']).isEmpty ? '价格规则' : _s(r['ruleName']), _s(r['ruleCode'])),
      ],
      if (items.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('对方主体核对', style: _sans(context, size: 12, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        _settlementCounterpartyCheck(context, items, _map(links['partner']), _supplier ? '供应商' : '渠道', links['partnerCounterparties']),
      ],
    ]));
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

  /// 顶部关系链：和列表卡片同一条——供应商主体 › 供应商 › 本产品 › 结算，下面是同一句状态说明。
  /// 渠道产品的渠道放在标题下的标签里（见 [_channelChip]），不进这条链。
  Widget _detailChain(BuildContext context, Map<String, dynamic> d) {
    final (segs, hint, hintColor) = _productChain(context, _cardLike(d), widget.side);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _relationChain(context, [
          ...segs.take(2),
          _ChainSeg('产品与结算', '本产品', sub: '${_list(d['settlementItems']).length} 条结算规则', current: true),
        ]),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: _chainHint(context, hint, hintColor),
          ),
      ],
    );
  }

  /// 渠道产品标题下的渠道标签：点进渠道详情；顺带写渠道主体（没关联写「待补」，不标红）。
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
                  linked ? '渠道主体 ${_subjectDisplay(partner['subjectName'])}' : '渠道主体待补',
                  style: _sans(context, size: 10.5, color: linked ? _kInk2 : _kCopper),
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
            if (double.tryParse(_s(p['unitPrice'])) != null) ('单价', _yuan(p['unitPrice'])),
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
      '3' => '档位见下方',
      _ => '',
    };
    final effective = _s(it['effectiveTime']);
    final expire = _s(it['expireTime']);
    return [
      _kv(context, '账单类型', _s(it['billTypeL3Name'])),
      _kv(context, '结算方式', [_s(it['settleMethodLabel']), value].where((e) => e.isNotEmpty).join(' · ')),
      if (_s(it['formulaName']).isNotEmpty) _kv(context, '计算公式', _s(it['formulaName'])),
      if (_s(it['thresholdAmount']).isNotEmpty) _kv(context, '门槛金额', _yuan(it['thresholdAmount'])),
      _kv(context, '签约双方', '我方 ${_s(it['ourEntity']).isEmpty ? '—' : _s(it['ourEntity'])} ⇄ 对方 ${_s(it['counterpartyEntity']).isEmpty ? '—' : _s(it['counterpartyEntity'])}'),
      _kv(
        context,
        '有效期',
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
    bool showValue = true,
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
          if (showValue) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: _num(context, size: 14)),
                Text(valueLabel, style: _sans(context, size: 10, color: _kMute)),
              ],
            ),
          ],
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
                if (status == '停用' || status == '待启用') ...[
                  const SizedBox(height: 4),
                  _tag(context, status, status == '停用' ? _Tone.grey : _Tone.copper),
                ],
              ],
            ),
          ],
        ),
        _miniChain(context, segs),
        if (hint != null) _chainHint(context, hint, hintColor),
        if (side == 'supplier') _bizProductTierLine(context, p),
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
          _kind == 'promoter' ? '主体' : _legalLabel(_kind),
          linked ? (_s(p['subjectName']).isEmpty ? '主体档案不可用' : _subjectDisplay(p['subjectName'])) : _unlinkedValue(p['counterparties']),
          tone: linked ? _SegTone.normal : _SegTone.warn,
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
      if (!linked && _kind != 'promoter' && _list(p['counterparties']).isNotEmpty) {
        children.add(Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: _cardDeco(context, radius: 16),
          child: ExpansionTile(
            initiallyExpanded: false,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text('该$_kindLabel结算规则涉及的对方公司', style: _sans(context, size: 12, weight: FontWeight.w600)),
            subtitle: Text('全部产品汇总 · 按规则数量展示前 5 家', style: _sans(context, size: 10.5, color: _kMute)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              _counterpartyList(context, p['counterparties']),
              const SizedBox(height: 6),
              Text(
                '同名主体档案仅供核对。请确认实际签约关系后再关联，不能按规则数量最多直接认定主体。',
                style: _sans(context, size: 10.5, color: _kMute, height: 1.5),
              ),
            ],
          ),
        ));
      }
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
      ('已审核产品', '${_count(effective)} 个'),
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
    if (eff != null && eff.isAfter(now)) return ('未开始', _Tone.grey);
    if (exp != null && exp.isBefore(now)) return ('已到期', _Tone.grey);
    final days = _daysUntil(r['expireTime']);
    if (days != null && days <= 30) return (days <= 0 ? '今天到期' : '$days 天到期', _Tone.copper);
    return ('执行中', _Tone.purple);
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
      final tierRules = _list(d['tierRules']);
      final currentParties = rules.map((r) => _s(r['counterpartyEntity']).toLowerCase()).toSet();
      final counterparties = _list(links['partnerCounterparties'])
          .where((c) => currentParties.contains(_s(c['name']).toLowerCase()))
          .toList();
      final name = _s(p['productName']).isEmpty ? widget.title : _s(p['productName']);
      final kindLabel = _supplier ? '供应商' : '渠道';
      final subjectName = _s(partner['subjectName']);
      children
        ..add(_relationChain(context, [
          // 渠道 / 供应商档案上的主体，对应规则里的「对方」；我方主体在每条规则的「签约双方」里。
          _ChainSeg(
            '$kindLabel主体',
            subjectName.isEmpty ? (_suggestedSubjects(counterparties).isEmpty ? '待补' : '待补 · 待确认') : _subjectDisplay(subjectName),
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
          ..add(_bizSpaced([for (final r in rules) _ruleCard(context, r, tierRules)]));
      }
      children
        ..add(_bizSection(context, '阶梯与价格规则', count: tierRules.length))
        ..add(Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: tierRules.isEmpty ? 0 : 8),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
          decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(12)),
          child: Text(_tierIntro(widget.side, rules, tierRules), style: _sans(context, size: 11, color: _kInk2, height: 1.6)),
        ));
      if (tierRules.isNotEmpty) children.add(_bizSpaced([for (final r in tierRules) _tierRuleCard(context, r)]));
      if (rules.isNotEmpty) {
        children
          ..add(_bizSection(context, '对方主体核对', note: '规则「对方」vs $kindLabel档案上的主体'))
          ..add(_settlementCounterpartyCheck(context, rules, partner, kindLabel, counterparties));
      }
    }
    return _bizSubPage(context, title: '结算', onRefresh: _load, children: children);
  }

  Widget _summary(BuildContext context, List<Map<String, dynamic>> rules) {
    final statuses = [for (final r in rules) _ruleStatus(r).$1];
    final active = statuses.where((s) => s == '执行中' || s.endsWith('到期') && s != '已到期').length;
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
          _bizCellGrid(context, [('规则', '${rules.length} 条'), ('执行中', '$active 条'), ('30 天内到期', '$soon 条')]),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('这个产品还没有结算规则', style: _sans(context, size: 12, color: _kMute)),
            )
          else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text('有效期', style: _sans(context, size: 12, weight: FontWeight.w700)),
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

  Widget _ruleCard(BuildContext context, Map<String, dynamic> r, List<Map<String, dynamic>> tierRules) {
    final (label, tone) = _ruleStatus(r);
    final eff = _s(r['effectiveTime']);
    final exp = _s(r['expireTime']);
    final tiered = _s(r['settleMethod']) == '3';
    final value = tiered ? '档位见下' : _ruleShort(_s(r['settleMethod']), r['settlementRatio'], r['unitPrice'], '');
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
          if (tiered && _s(r['settlementRatio']).isNotEmpty) kv('结算比例', _plain(r['settlementRatio']), mono: true),
          // 签约双方：我方（我们自己的公司）⇄ 对方（签合同、开票、收付款的那家），一行看清，不和上面的「主体」混。
          kv('签约双方', '我方 ${_s(r['ourEntity']).isEmpty ? '—' : _s(r['ourEntity'])}  ⇄  对方 ${_s(r['counterpartyEntity']).isEmpty ? '—' : _s(r['counterpartyEntity'])}'),
          kv('有效期', '${eff.isEmpty ? '—' : _date(eff)} → ${exp.isEmpty ? '长期' : _date(exp)}', mono: true),
          if (tiered) _tierPriceInline(context, r, tierRules),
        ],
      ),
    );
  }


}

Widget _settlementCounterpartyCheck(BuildContext context, List<Map<String, dynamic>> rules, Map<String, dynamic> partner, String kindLabel, Object? counterparties) {
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
      // 渠道级汇总只用来核实当前规则是否有同名档案，不在产品页展示其他公司。
      final names = parties.map((name) => name.trim().toLowerCase()).toSet();
      final matches = _suggestedSubjects(counterparties)
          .where((c) => names.contains(_s(c['name']).trim().toLowerCase()))
          .map((c) => _s(c['name']))
          .toSet();
      text = '${parties.isEmpty ? '当前规则未填写结算对方。' : '结算对方：${parties.join('、')}。'}\n'
          '$kindLabel「${_s(partner['name'])}」尚未关联主体，暂时无法核对。'
          '${matches.isEmpty ? '' : '\n已找到「${matches.join('、')}」的同名主体档案，可前往$kindLabel档案确认；同名不代表已确认是同一家公司。'}';
      color = _kCopper;
      soft = _kCopperSoft;
      onTap = () => _openBizPartner(context, kindLabel == '供应商' ? 'supplier' : 'channel', _s(partner['id']), name: _s(partner['name']));
      action = '查看$kindLabel档案 ›';
    } else if (parties.isEmpty) {
      text = '规则里没有填写对方主体。';
      color = _kInk2;
      soft = _kPanel;
    } else {
      final bad = parties.where((e) => !same(e)).toList();
      if (bad.isEmpty) {
        text = '规则「对方」与$kindLabel主体「${full.isEmpty ? short : full}」是同一家。';
        color = _kDeep;
        soft = _kLavender;
      } else {
        text = '规则「对方」${bad.join('、')} 与$kindLabel主体「${full.isEmpty ? short : full}」不是同一家，请确认是否签错主体。';
        color = _kCoral;
        soft = _kCoralSoft;
      }
      onTap = () => _openBizSubject(context, subjectId, short);
      action = '看$kindLabel主体 ›';
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

// ── 主体页（合作主体主体档案）──

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
          _ChainSeg('主体', short.isEmpty ? (widget.title.isEmpty ? '—' : widget.title) : short, current: true),
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
                ('已审核', '${_count(_i(totals['effectiveProducts']))} 个'),
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
    return _bizSubPage(context, title: '主体', onRefresh: _load, children: children);
  }

  Widget _emptyNote(BuildContext context, String text) => Container(
    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
    decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: _sans(context, size: 11, color: _kInk2, height: 1.6)),
  );
}

// ═════════════════════════════ 业务脉搏 · 画法 ═════════════════════════════
//
//   链路分段键（产品列表「全部 / 已连接 / 可用 / 已配结算」）与总览缓存。新版 hero 的画法见文末「业务脉搏 · 方案 A」。

const _kRingKeys = ['', 'connected', 'usable', _kChainThrough];

/// 上一次拿到的业务总览：切走再回来时先用它画，同时后台刷新。
Map<String, dynamic>? _bizOverviewCache;
String _chainLabel(String key) => switch (key) {
  '' => '全部',
  'connected' => '已连接供给产品',
  'usable' => '审核生效且启用',
  _kChainThrough => '渠道及供给侧均已配结算',
  _ => _chainSeg(key).$1,
};

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

// ═════════════════════════════ 业务脉搏 · 方案 A（一屏一图 · 横滑） ═════════════════════════════
//
//   顶部四格分段（阶梯 / 跨档进度 / 推送 / 到期）与左右滑动同步，每页 = 一句读数 + 一张图：
//     · 阶梯：选中规则本期的累计基数爬坡线（期初 → 各档到档时间 → 最近一次计算，都是真实锚点）、
//             档位门槛台阶、按本期日均外推的预测锥与到档日期区间；长按图可读任一天的数；
//     · 跨档进度：本期全部阶梯规则按最快到下一档排序，可按 可跨档 / 难达 / 满档 筛选、上下滑动；点行切到「阶梯」看大图；
//       阶梯页顶部有 ‹ 当前规则 › 切换条，点中间可从全部规则里搜索选择，右侧是档位明细；
//     · 推送：今日逐条推送，针高 = 耗时、颜色 = 推送类型、珊瑚色 = 失败；下方镜像是每 10 分钟的结算回传批次；
//     · 到期：未来 30 天两侧结算明细到期点阵，7 天内用临期色；点进去 = 结算列表「30 天内到期」。
//   数据：business-go Overview 的 tierBoard / pulse.events / settleExpiry（见 business-go internal/mobile/hero.go）。

const _kTypeSettle = Color(0xFF7B5CD8);
const _kTypePrice = Color(0xFF2E8FB8);
const _kTypeBill = Color(0xFFD0619A);
const _kWarnMark = Color(0xFFB5791A);

/// 推送类型 → (名称, 颜色)；未知类型用灰。
(String, Color) _pushTypeTone(String v) => switch (v.toUpperCase()) {
  'PRODUCT_SETTLEMENT' => ('产品结算配置', _kTypeSettle),
  'PRICE_RULE' => ('价格规则', _kTypePrice),
  'BILL_CONFIG' => ('账单配置', _kTypeBill),
  _ => (v.isEmpty ? '其他' : v, _kChainGrey),
};

double? _hNum(Object? v) => v is num ? v.toDouble() : double.tryParse(_s(v));

/// 「2026-11-10 13:44:00」→ 本地墙钟时间（资管库按北京时间存，这里不做时区换算）。
DateTime? _hDt(Object? v) {
  final s = _s(v);
  if (s.length >= 19) return DateTime.tryParse(s.substring(0, 19).replaceFirst(' ', 'T'));
  if (s.length >= 10) return DateTime.tryParse(s.substring(0, 10));
  return null;
}

String _hMd(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// 一条阶梯规则本期的进度（tierBoard.rules[i]）。
class _TierRule {
  _TierRule(this.m)
    : tiers = [for (final t in _list(m['tiers'])) (_hNum(t['min']) ?? 0.0, _rate(t['rate']))],
      reaches = [
        for (final e in _list(m['reaches']))
          if (_hDt(e['at']) != null) (_i(e['level']) ?? 0, _hDt(e['at'])!),
      ];

  final Map<String, dynamic> m;
  final List<(double, String)> tiers;
  final List<(int, DateTime)> reaches;

  String get id => _s(m['ruleId']);
  String get code => _s(m['code']);
  String get name => _s(m['name']).isEmpty ? '阶梯规则' : _s(m['name']);
  String get title => code.isEmpty ? name : '$code $name';
  double get stat => _hNum(m['stat']) ?? 0;
  int get level => _i(m['level']) ?? 0;
  bool get full => m['full'] == true;
  bool get reachable => m['reachable'] == true;
  double? get next => _hNum(m['next']);
  double? get gap => _hNum(m['gap']);
  double get rate => _hNum(m['ratePerDay']) ?? 0;
  String get discount => _rate(m['discount']);
  DateTime? get start => _hDt(m['periodStart']);
  DateTime? get end => _hDt(m['periodEnd']);
  DateTime? get asOf => _hDt(m['asOf']);
  DateTime? get eta => _hDt(m['eta']);
  DateTime? get etaEarly => _hDt(m['etaEarly']);
  DateTime? get etaLate => _hDt(m['etaLate']);

  /// 到下一档的进度 0–1；满档 = 1。
  double get frac {
    final n = next;
    if (full || n == null) return 1;
    final prev = level > 0 && level <= tiers.length ? tiers[level - 1].$1 : 0.0;
    if (n <= prev) return 0;
    return ((stat - prev) / (n - prev)).clamp(0.0, 1.0).toDouble();
  }

  /// 爬坡锚点：期初 0 → 各档到档时间（取门槛）→ 最近一次计算时的基数。
  List<(DateTime, double)> get anchors {
    final s = start, a = asOf;
    if (s == null || a == null) return const [];
    final out = <(DateTime, double)>[(s, 0)];
    for (final (lv, at) in reaches) {
      if (lv < 1 || lv > tiers.length) continue;
      final v = tiers[lv - 1].$1;
      if (v <= 0 || v > stat || at.isBefore(s) || at.isAfter(a)) continue;
      if (at.isBefore(out.last.$1) || v < out.last.$2) continue;
      out.add((at, v));
    }
    out.add((a, stat));
    return out;
  }

  /// 任一时刻的读数：(基数, 预测下沿, 预测上沿, 是否预测)。
  (double, double, double, bool) valueAt(DateTime t) {
    final a = asOf;
    if (a != null && t.isAfter(a)) {
      final days = t.difference(a).inMinutes / 1440;
      return (stat + days * rate, stat + days * rate * 0.7, stat + days * rate * 1.3, true);
    }
    final pts = anchors;
    for (var i = 1; i < pts.length; i++) {
      if (!t.isAfter(pts[i].$1)) {
        final (t0, v0) = pts[i - 1];
        final (t1, v1) = pts[i];
        final span = t1.difference(t0).inMinutes;
        final f = span <= 0 ? 1.0 : (t.difference(t0).inMinutes / span).clamp(0.0, 1.0);
        final v = v0 + (v1 - v0) * f;
        return (v, v, v, false);
      }
    }
    return (stat, stat, stat, false);
  }

  int levelOf(double v) {
    var lv = 0;
    for (var i = 0; i < tiers.length; i++) {
      if (v >= tiers[i].$1) lv = i + 1;
    }
    return lv;
  }
}

/// 画图用的一组已按明暗解析过的颜色与字样。
class _HeroInk {
  _HeroInk(BuildContext context)
    : purple = _fg(context, _kPurple),
      deep = _fg(context, _kDeep),
      ink = _fg(context, _kInk),
      ink2 = _fg(context, _kInk2),
      mute = _fg(context, _kMute),
      edge = _ln(context, _kEdge),
      line = _ln(context, _kLine),
      card = _bg(context, Colors.white),
      panel = _bg(context, _kPanel),
      coral = _fg(context, _kCoral),
      warn = _fg(context, _kWarnMark),
      warnInk = _fg(context, _kCopper),
      warnSoft = _bg(context, _kCopperSoft),
      mono = LhTypography.mono(context: context, size: 9, color: _fg(context, _kMute)),
      sans = LhTypography.sans(context: context, size: 9, color: _fg(context, _kInk2));

  final Color purple, deep, ink, ink2, mute, edge, line, card, panel, coral, warn, warnInk, warnSoft;
  final TextStyle mono, sans;
}

void _paintText(Canvas c, String text, TextStyle style, Offset at, {TextAlign align = TextAlign.left, Color? halo}) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  var dx = at.dx;
  if (align == TextAlign.right) dx -= tp.width;
  if (align == TextAlign.center) dx -= tp.width / 2;
  if (halo != null) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = halo;
    (TextPainter(text: TextSpan(text: text, style: style.copyWith(foreground: stroke)), textDirection: TextDirection.ltr)..layout())
        .paint(c, Offset(dx, at.dy));
  }
  tp.paint(c, Offset(dx, at.dy));
}

double _textWidth(String text, TextStyle style) =>
    (TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout()).width;

void _dashLine(Canvas c, Offset a, Offset b, Paint p, {double dash = 4, double gap = 3}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final u = d / len;
  for (double s = 0; s < len; s += dash + gap) {
    c.drawLine(a + u * s, a + u * math.min(s + dash, len), p);
  }
}

void _hatch(Canvas c, Rect r, Color color) {
  if (r.width <= 0 || r.height <= 0) return;
  c.save();
  c.clipRect(r);
  final p = Paint()
    ..color = color
    ..strokeWidth = 1;
  for (double x = r.left - r.height; x < r.right; x += 5) {
    c.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), p);
  }
  c.restore();
}

class _BizPulseHero extends StatefulWidget {
  const _BizPulseHero({
    this.initialPage = 0,
    this.ruleOnly = false,
    required this.overview,
    required this.service,
    required this.loading,
    required this.onOpenPush,
    required this.onOpenExpiring,
  });

  final bool ruleOnly;
  final int initialPage;
  final LighthouseService service;
  final Map<String, dynamic> overview;
  final bool loading;
  final VoidCallback onOpenPush;
  final VoidCallback onOpenExpiring;

  @override
  State<_BizPulseHero> createState() => _BizPulseHeroState();
}

class _BizPulseHeroState extends State<_BizPulseHero> {
  List<String> get _lenses => widget.ruleOnly ? const ['跨档进度', '阶梯'] : const ['跨档进度', '阶梯', '推送', '到期'];
  static const _slideHeight = 300.0;
  static const _tierPad = EdgeInsets.fromLTRB(2, 14, 50, 15);

  late final PageController _pc = PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;
  String _ruleId = '';
  String _raceFilter = 'all'; // 跨档进度筛选：all / reach / hard / full
  double? _scrub; // 阶梯图上长按的位置：本期进度 0–1
  bool _showDef = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() {
      _page = i;
      _scrub = null;
    });
    _pc.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  List<_TierRule> get _rules => [for (final r in _list(_map(widget.overview['tierBoard'])['rules'])) _TierRule(r)];

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    _TierRule? pick;
    for (final r in rules) {
      if (r.id == _ruleId) pick = r;
    }
    pick ??= rules.isEmpty ? null : rules.first;
    final ink = _HeroInk(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lensBar(context),
        const SizedBox(height: 10),
        Container(
          height: _slideHeight + 24,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _bg(context, Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _ln(context, _kHeroPanelEdge), width: 0.9),
          ),
          child: PageView(
            controller: _pc,
            onPageChanged: (i) => setState(() {
              _page = i;
              _scrub = null;
            }),
            children: [
              _raceSlide(context, ink, rules, pick),
              _tierSlide(context, ink, rules, pick),
              if (!widget.ruleOnly) ...[_pushSlide(context, ink), _expirySlide(context, ink)],
            ],
          ),
        ),
        if (!widget.ruleOnly && !widget.loading) ...[
          const SizedBox(height: 10),
          _tilesRow(context, rules),
        ],
        const SizedBox(height: 8),
        _dotsRow(context),
        if (_showDef) ...[const SizedBox(height: 6), _defBox(context)],
      ],
    );
  }

  /// 底部三组指标格（同灯塔 Hero 下面那排）：阶梯 / 推送 / 结算。只放接口给的数，不编环比。
  Widget _tilesRow(BuildContext context, List<_TierRule> rules) {
    final o = widget.overview;
    final board = _map(o['tierBoard']);
    final pulse = _map(o['pulse']);
    final expiry = _map(o['settleExpiry']);
    String n(Object? v) => _i(v) == null ? '—' : _count(_i(v));
    final full = rules.where((r) => r.full).length;
    final p95 = _i(pulse['costP95']);
    final failed = _i(o['todayPushFailed']) ?? 0;
    final abnormal = _i(o['todayReturnAbnormal']) ?? 0;
    final groups = <(String, Color, VoidCallback, List<(String, String, String, Color)>)>[
      ('阶梯', _kLensColors[0], () => _go(0), [
        ('本期规则', n(board['total'] ?? rules.length), '条', _kInk),
        ('本期可跨', n(board['periodCross']), '条', _kHeroNum),
        ('已满档', _count(full), '条', _kInk),
      ]),
      ('推送', _kLensColors[2], widget.onOpenPush, [
        ('今日推送', n(o['todayPushes']), '次', _kInk),
        ('失败', _count(failed), '次', failed > 0 ? _kCoral : _kInk),
        ('P95 耗时', p95 == null ? '—' : _count(p95), p95 == null ? '' : 'ms', _kInk),
      ]),
      ('结算', _kLensColors[3], widget.onOpenExpiring, [
        ('30 天到期', n(expiry['total']), '条', _kInk),
        ('本周到期', n(expiry['week']), '条', _kInk),
        ('回传异常', _count(abnormal), '批', abnormal > 0 ? _kCoral : _kInk),
      ]),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              label: '${groups[g].$1}：${[for (final r in groups[g].$4) '${r.$1} ${r.$2}${r.$3}'].join('，')}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: groups[g].$3,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  decoration: BoxDecoration(
                    color: _bg(context, Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ln(context, _kHeroPanelEdge), width: 0.9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: _fg(context, groups[g].$2), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text(groups[g].$1, style: _sans(context, size: 10.5, weight: FontWeight.w600, color: groups[g].$2)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (final r in groups[g].$4)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: _ln(context, _kLine), width: 0.8))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.$1, style: _sans(context, size: 10, color: _kInk2)),
                              const SizedBox(height: 1),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: r.$2, style: LhTypography.mono(context: context, size: 14, weight: FontWeight.w500, color: _fg(context, r.$4))),
                                    if (r.$3.isNotEmpty)
                                      TextSpan(text: r.$3, style: _sans(context, size: 9, color: _kInk2)),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 视角切换：灯塔「本期合计」图例那种带色点的下划线 tab，不再是灰底分段控件。
  Widget _lensBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _ln(context, _kHeroEdge), width: 1))),
      child: Row(
        children: [
          for (var i = 0; i < _lenses.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Semantics(
              button: true,
              selected: i == _page,
              label: _lenses[i],
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _go(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == _page ? _fg(context, _kLensColors[i % _kLensColors.length]) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _fg(context, _kLensColors[i % _kLensColors.length]).withValues(alpha: i == _page ? 1 : 0.45),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _lenses[i],
                        style: _sans(
                          context,
                          size: 12.5,
                          weight: i == _page ? FontWeight.w600 : FontWeight.w400,
                          color: i == _page ? _kHeroNum : _kHeroMute,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dotsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showDef = !_showDef),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
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
          ),
        ),
      ],
    );
  }

  Widget _defBox(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(10)),
      child: Text(
        '阶梯：本期有计算记录的阶梯计费规则。资管只保留最新一次计算，所以爬坡线只连真实锚点：期初、各档到档时间（取门槛）、最近一次计算的基数。'
        '预测按本期日均（基数 ÷ 已过天数）外推，区间按日均 ±30%；到期末也到不了下一档的记为「本期难达」。长按图可读任一天的数。\n'
        '跨档进度：一段 = 一档，填充长度表示当前进度；按最快到下一档排序。「本周」到本周日 24 点。\n'
        '推送：今日每条产品推送（最多取最新 600 条），针高 = 耗时，颜色 = 推送类型，珊瑚色 = 失败；下方是每 10 分钟的结算回传批次，珊瑚色 = 有异常批次。\n'
        '到期：渠道、供应商两侧结算明细的失效时间落在未来 30 天内的条数，每列一天；与结算列表「30 天内到期」同口径。',
        style: _sans(context, size: 10.5, color: _kInk2, height: 1.6),
      ),
    );
  }

  // ── 读数行 ──

  TextSpan _b(BuildContext context, String t, {Color color = _kInk}) =>
      TextSpan(text: t, style: LhTypography.mono(context: context, size: 10.5, weight: FontWeight.w600, color: _fg(context, color)));

  Widget _kpi(BuildContext context, String big, String unit, List<InlineSpan> line1, List<InlineSpan> line2) {
    final style = _sans(context, size: 10.5, color: _kInk2, height: 1.4);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: big, style: LhTypography.number(context: context, size: 24, color: _fg(context, _kHeroNum))),
                TextSpan(text: unit, style: _sans(context, size: 11.5, weight: FontWeight.w500, color: _kInk2)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: line1), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                if (line2.isNotEmpty) Text.rich(TextSpan(children: line2), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _kpi(context, '—', '', [const TextSpan(text: '加载中…')], const []),
      const SizedBox(height: 8),
      Expanded(
        child: DecoratedBox(decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(10))),
      ),
    ],
  );

  Widget _empty(BuildContext context, String text) => Center(
    child: Text(text, textAlign: TextAlign.center, style: _sans(context, size: 11, color: _kMute, height: 1.5)),
  );

  // ── 1. 阶梯 ──

  void _scrubAt(_TierRule r, double dx, double width) {
    final w = width - _tierPad.left - _tierPad.right;
    if (w <= 0) return;
    setState(() => _scrub = ((dx - _tierPad.left) / w).clamp(0.0, 1.0).toDouble());
  }

  /// 选中某条规则看阶梯走势（不在阶梯页时滑过去）。
  void _pickRule(_TierRule r) {
    setState(() {
      _ruleId = r.id;
      _scrub = null;
    });
    if (_page != 1) _go(1);
  }

  /// 阶梯页顶部：‹ 当前规则（第 i / N 条，点开可选全部）› + 档位明细。
  Widget _ruleSwitcher(BuildContext context, _HeroInk ink, List<_TierRule> rules, _TierRule r) {
    final idx = rules.indexOf(r);
    final many = rules.length > 1;
    void step(int d) {
      if (!many) return;
      final n = rules[(idx + d + rules.length) % rules.length];
      setState(() {
        _ruleId = n.id;
        _scrub = null;
      });
    }

    Widget square(IconData icon, String label, VoidCallback? onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 17, color: _fg(context, onTap == null ? _kMute : _kDeep)),
        ),
      ),
    );

    return SizedBox(
      height: 28,
      child: Row(
        children: [
          square(Icons.chevron_left_rounded, '上一条规则', many ? () => step(-1) : null),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              label: '当前规则 ${r.name}，第 ${idx + 1} 条，共 ${rules.length} 条，点按切换',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openRulePicker(context, ink, rules, r),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: ink.purple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ink.purple.withValues(alpha: 0.18), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${idx + 1}/${rules.length}',
                        style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w600, color: _fg(context, _kDeep)),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(context, size: 11.5, weight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.unfold_more_rounded, size: 15, color: _fg(context, _kDeep)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          square(Icons.chevron_right_rounded, '下一条规则', many ? () => step(1) : null),
          const SizedBox(width: 6),
          square(Icons.table_rows_outlined, '档位明细', () => _showRuleDetail(context, r)),
        ],
      ),
    );
  }

  /// 全部阶梯规则的选择面板：可搜索，点一条即切到它的阶梯走势。
  void _openRulePicker(BuildContext context, _HeroInk ink, List<_TierRule> rules, _TierRule current) {
    var q = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg(context, Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final shown = q.isEmpty ? rules : [for (final r in rules) if (r.name.contains(q) || r.code.contains(q)) r];
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 2),
                      child: Row(
                        children: [
                          Expanded(child: Text('切换阶梯规则 · ${rules.length} 条', style: _sans(ctx, size: 15, weight: FontWeight.w700))),
                          IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close), tooltip: '关闭'),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text('按预计跨档时间排序；点一条看它的阶梯走势。', style: _sans(ctx, size: 11, color: _kMute)),
                    ),
                    if (rules.length > 6)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          onChanged: (v) => setSheet(() => q = v.trim()),
                          style: _sans(ctx, size: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '搜索规则名称',
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            filled: true,
                            fillColor: _bg(ctx, _kPanel),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('没有匹配的规则', style: _sans(ctx, size: 12, color: _kMute))),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final r = shown[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: _raceRow(
                                ctx,
                                ink,
                                r,
                                hot: r.reachable && _withinWeek(r),
                                selected: r.id == current.id,
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _pickRule(r);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tierSlide(BuildContext context, _HeroInk ink, List<_TierRule> rules, _TierRule? r) {
    if (widget.loading) return _skeleton(context);
    if (r == null) {
      return _empty(context, widget.overview['tierBoard'] == null ? '阶梯数据暂不可用' : '本期还没有阶梯规则的计算记录');
    }
    final nextLv = r.level + 1;
    final line1 = <InlineSpan>[
      if (r.full)
        TextSpan(text: '已到最高档 · 折扣 ${r.discount}')
      else if (r.gap != null) ...[TextSpan(text: '距 $nextLv 档 '), _b(context, '¥${_wan(r.gap)}'), TextSpan(text: ' · 当前折扣 ${r.discount}')],
    ];
    var line2 = <InlineSpan>[];
    final scrub = _scrub;
    final start = r.start, end = r.end;
    if (scrub != null && start != null && end != null) {
      final t = start.add(Duration(minutes: (end.difference(start).inMinutes * scrub).round()));
      final (v, lo, hi, forecast) = r.valueAt(t);
      line2 = forecast
          ? [
              _b(context, _hMd(t)),
              const TextSpan(text: ' 预测 '),
              _b(context, '¥${_wan(v)}'),
              TextSpan(text: '（${_wan(lo)}–${_wan(hi)}）· ${r.levelOf(v)} 档'),
            ]
          : [
              _b(context, _hMd(t)),
              const TextSpan(text: ' 累计 '),
              _b(context, '¥${_wan(v)}'),
              TextSpan(text: ' · ${r.levelOf(v)} 档'),
            ];
    } else if (r.full) {
      line2 = [const TextSpan(text: '当前折扣 '), _b(context, r.discount), const TextSpan(text: ' · 本期基数 '), _b(context, '¥${_wan(r.stat)}')];
    } else if (r.reachable && r.eta != null) {
      line2 = [
        const TextSpan(text: '本期日均 '),
        _b(context, '¥${_wan(r.rate)}'),
        const TextSpan(text: '，预计 '),
        _b(context, '${_hMd(r.eta!)} 到达下一档', color: _kDeep),
        if (r.etaEarly != null && r.etaLate != null) TextSpan(text: '（${_hMd(r.etaEarly!)}–${_hMd(r.etaLate!)}）'),
      ];
    } else {
      line2 = [const TextSpan(text: '本期日均 '), _b(context, '¥${_wan(r.rate)}'), TextSpan(text: '，到期末也到不了 $nextLv 档')];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ruleSwitcher(context, ink, rules, r),
        const SizedBox(height: 6),
        _kpi(context, '${r.level}', '档', line1, line2),
        const SizedBox(height: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _scrubAt(r, d.localPosition.dx, box.maxWidth),
              onLongPressStart: (d) => _scrubAt(r, d.localPosition.dx, box.maxWidth),
              onLongPressMoveUpdate: (d) => _scrubAt(r, d.localPosition.dx, box.maxWidth),
              onLongPressEnd: (_) => setState(() => _scrub = null),
              child: CustomPaint(
                size: Size(box.maxWidth, box.maxHeight),
                painter: _TierClimbPainter(rule: r, ink: ink, pad: _tierPad, scrub: _scrub),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 2. 跨档进度 ──

  Widget _raceSlide(BuildContext context, _HeroInk ink, List<_TierRule> rules, _TierRule? pick) {
    if (widget.loading) return _skeleton(context);
    if (rules.isEmpty) {
      return _empty(context, widget.overview['tierBoard'] == null ? '阶梯数据暂不可用' : '本期还没有阶梯规则的计算记录');
    }
    final board = _map(widget.overview['tierBoard']);
    final total = _i(board['total']) ?? rules.length;
    final week = _i(board['weekCross']) ?? 0;
    final period = _i(board['periodCross']) ?? 0;
    _TierRule? first;
    for (final r in rules) {
      if (r.reachable && first == null) first = r;
    }
    final groups = <(String, String, List<_TierRule>)>[
      ('all', '全部', rules),
      ('reach', '本期可跨档', [for (final r in rules) if (r.reachable) r]),
      ('hard', '本期难达', [for (final r in rules) if (!r.reachable && !r.full) r]),
      ('full', '已满档', [for (final r in rules) if (r.full) r]),
    ];
    var shown = rules;
    for (final g in groups) {
      if (g.$1 == _raceFilter) shown = g.$3;
    }
    final line2 = <InlineSpan>[
      TextSpan(text: rules.length < total ? '按预计跨档时间排序 · 显示前 ${rules.length} 条' : '按预计跨档时间排序 · 点一条看阶梯走势'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpi(context, '$week', '条', [
          const TextSpan(text: '本周可能跨档 · 本期 '),
          _b(context, '$period'),
          TextSpan(text: ' / $total 条阶梯规则'),
        ], line2),
        const SizedBox(height: 6),
        SizedBox(
          height: 22,
          child: Row(
            children: [
              for (final (key, label, list) in groups)
                if (key == 'all' || list.isNotEmpty) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _raceFilter = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: key == _raceFilter ? ink.purple.withValues(alpha: 0.12) : _bg(context, _kPanel),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$label '),
                            TextSpan(
                              text: '${list.length}',
                              style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w600, color: _fg(context, key == _raceFilter ? _kDeep : _kInk2)),
                            ),
                          ],
                        ),
                        style: _sans(context, size: 10.5, weight: key == _raceFilter ? FontWeight.w600 : FontWeight.w400, color: key == _raceFilter ? _kDeep : _kInk2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: shown.isEmpty
              ? _empty(context, '这一类没有规则')
              : ShaderMask(
                  // 底部渐隐，提示还能往下滑。
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, rect.height <= 0 ? 1 : (1 - 14 / rect.height).clamp(0.0, 1.0).toDouble(), 1],
                  ).createShader(rect),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    physics: const ClampingScrollPhysics(),
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final r = shown[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _raceRow(
                          context,
                          ink,
                          r,
                          hot: r == first || (r.reachable && _withinWeek(r)),
                          selected: r == pick,
                          onTap: () => _pickRule(r),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  bool _withinWeek(_TierRule r) {
    final e = r.eta, a = r.asOf;
    if (e == null || a == null) return false;
    final day = DateTime(a.year, a.month, a.day);
    return e.isBefore(day.add(Duration(days: 8 - a.weekday)));
  }

  void _showRuleDetail(BuildContext context, _TierRule r) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: _bg(context, Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('规则明细', style: _sans(ctx, size: 15, weight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close), tooltip: '关闭'),
              ]),
              Text(r.name, style: _sans(ctx, size: 14, weight: FontWeight.w600)),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: () { Navigator.of(ctx).pop(); Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => LighthouseRuleLedgerPage(service: widget.service, rule: r.m))); }, icon: const Icon(Icons.table_chart_outlined, size: 18), label: const Text('查看关联日月年表')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () { Navigator.of(ctx).pop(); Navigator.of(context).pushNamed('/tier', arguments: {'ruleId': r.id}); }, icon: const Icon(Icons.insights_outlined, size: 18), label: const Text('阶梯详情与灯塔经营')),
              const SizedBox(height: 10),
              SelectableText('规则编码：${r.code.isEmpty ? '—' : r.code}', style: _sans(ctx, size: 12, color: _kInk2)),
              const SizedBox(height: 6),
              Text('本期周期：${_date(r.m['periodStart'])} 至 ${_date(r.m['periodEnd'])}', style: _sans(ctx, size: 12, color: _kInk2)),
              const SizedBox(height: 6),
              Text('当前第 ${r.level} 档 · 本期基数 ¥${_wan(r.stat)}', style: _sans(ctx, size: 12)),
              const SizedBox(height: 6),
              Text(r.full ? '已到最高档' : '距下一档：¥${_wan(r.gap)} · ${r.reachable && r.eta != null ? '预计 ${_hMd(r.eta!)} 跨档' : '本期预计难达'}', style: _sans(ctx, size: 12, color: _kDeep)),
              const SizedBox(height: 12),
              _miniTable(ctx, const ['档位', '起始基数（元）', '比例'], [for (var i = 0; i < r.tiers.length; i++) ['${i + 1} 档', _wan(r.tiers[i].$1), r.tiers[i].$2]], hit: r.level > 0 ? r.level - 1 : null),
              const SizedBox(height: 10),
              Text('预测依据：本期基数 ÷ 已过天数，按本期日均外推；预计日期会随实际业务量变化。', style: _sans(ctx, size: 11, color: _kMute, height: 1.5)),
              const SizedBox(height: 12),
              TextButton(onPressed: () { Navigator.of(ctx).pop(); _pickRule(r); }, child: const Text('查看阶梯走势')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _raceRow(BuildContext context, _HeroInk ink, _TierRule r, {required bool hot, required bool selected, VoidCallback? onTap}) {
    final right = r.full
        ? '满档 · ${r.discount}'
        : r.reachable && r.eta != null
        ? '差 ¥${_wan(r.gap)}  预计 ${_hMd(r.eta!)} 到达下一档'
        : '差 ¥${_wan(r.gap)} · 本期难达';
    return Semantics(
      button: true,
      label: '${r.name}，当前 ${r.level} 档，$right，查看阶梯走势',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => _pickRule(r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? ink.purple.withValues(alpha: 0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.name} · 第 ${r.level} 档',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(context, size: 10.5, weight: hot ? FontWeight.w600 : FontWeight.w400, color: hot ? _kInk : _kInk2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    right,
                    style: LhTypography.mono(context: context, size: 9.5, color: _fg(context, _kMute)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 2026-11-10 · 淡化：2px 细线、浅紫，快过档（本周可跨）稍深，满档更淡。
              SizedBox(
                height: 4,
                child: CustomPaint(
                  painter: _RaceTrackPainter(
                    segments: math.max(1, r.tiers.length),
                    level: r.level,
                    frac: r.frac,
                    full: r.full,
                    fill: _fg(context, r.full ? _kThinCapped : (hot ? _kThinNear : _kThinFill)),
                    track: _fg(context, const Color(0xFFEFEBF6)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3. 推送 ──

  Widget _pushSlide(BuildContext context, _HeroInk ink) {
    if (widget.loading) return _skeleton(context);
    final o = widget.overview;
    final pulse = _map(o['pulse']);
    var events = [
      for (final e in _list(pulse['events'])) (_hNum(e['minute']) ?? 0.0, _s(e['type']), _s(e['status']).toUpperCase(), _i(e['costMs'])),
    ];
    if (events.isEmpty) {
      // 老版本服务端只给 10 分钟分档：每条按档位中点画，不带耗时。
      events = [
        for (final p in _list(pulse['pushes']))
          for (var k = 0; k < (_i(p['count']) ?? 0); k++)
            ((_i(p['minute']) ?? 0) + 5.0, '', k < (_i(p['failed']) ?? 0) ? 'FAILED' : 'SUCCESS', null),
      ];
    }
    final returns = [for (final e in _list(pulse['returns'])) (_i(e['minute']) ?? 0, e['abnormal'] == true)];
    final total = _i(o['todayPushes']) ?? events.length;
    final failed = _i(o['todayPushFailed']) ?? events.where((e) => e.$3 == 'FAILED').length;
    final retTotal = _i(o['todayReturnBatches']) ?? returns.length;
    final retAbnormal = _i(o['todayReturnAbnormal']) ?? 0;
    final p50 = _i(pulse['costP50']), p95 = _i(pulse['costP95']);
    final last = _s(pulse['lastPushAt']);
    final gen = _s(o['generatedAt']);
    final nowMin = gen.length >= 16 ? (_i(gen.substring(11, 13)) ?? 0) * 60 + (_i(gen.substring(14, 16)) ?? 0) : 1440;
    final counts = <String, int>{};
    for (final e in events) {
      final name = _pushTypeTone(e.$2).$1;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final typeOrder = ['产品结算配置', '价格规则', '账单配置'];
    final legend = [
      for (final n in typeOrder)
        if (counts.containsKey(n)) (n, counts[n]!),
      for (final n in counts.keys)
        if (!typeOrder.contains(n)) (n, counts[n]!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpi(
          context,
          _count(total),
          '次',
          [
            const TextSpan(text: '失败 '),
            _b(context, _count(failed), color: failed > 0 ? _kCoral : _kInk),
            if (p50 != null) ...[const TextSpan(text: ' · 耗时 p50 '), _b(context, '${p50}ms')],
            if (p95 != null) ...[const TextSpan(text: ' · p95 '), _b(context, '${p95}ms')],
          ],
          [
            const TextSpan(text: '结算回传 '),
            _b(context, '${_count(retTotal)}${o['returnBatchesCapped'] == true ? '+' : ''}'),
            const TextSpan(text: ' 批 · 异常 '),
            _b(context, _count(retAbnormal), color: retAbnormal > 0 ? _kCoral : _kInk),
            if (last.length >= 16) ...[const TextSpan(text: ' · 最近推送 '), _b(context, last.substring(11, 16))],
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenPush,
            child: events.isEmpty && returns.isEmpty
                ? _empty(context, '今天还没有推送和结算回传')
                : CustomPaint(
                    size: Size.infinite,
                    painter: _PushScopePainter(
                      events: [for (final e in events) (e.$1, _fg(context, e.$3 == 'FAILED' ? _kCoral : _pushTypeTone(e.$2).$2), e.$4)],
                      returns: returns,
                      nowMinute: nowMin.toDouble(),
                      ink: ink,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 14,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (name, n) in legend) ...[
                    _legendDot(context, _fg(context, _pushTypeTone(_typeKey(name)).$2)),
                    Text(' $name ', style: _sans(context, size: 10, color: _kInk2)),
                    Text('$n', style: LhTypography.mono(context: context, size: 10, weight: FontWeight.w600, color: _fg(context, _kInk))),
                    const SizedBox(width: 10),
                  ],
                  _legendDot(context, ink.purple.withValues(alpha: 0.28)),
                  Text(' 结算回传', style: _sans(context, size: 10, color: _kInk2)),
                  if (failed > 0) ...[
                    const SizedBox(width: 10),
                    _legendDot(context, ink.coral),
                    Text(' 失败', style: _sans(context, size: 10, color: _kInk2)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _typeKey(String name) => switch (name) {
    '产品结算配置' => 'PRODUCT_SETTLEMENT',
    '价格规则' => 'PRICE_RULE',
    '账单配置' => 'BILL_CONFIG',
    _ => name,
  };

  Widget _legendDot(BuildContext context, Color c) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
  );

  // ── 4. 到期 ──

  Widget _expirySlide(BuildContext context, _HeroInk ink) {
    if (widget.loading) return _skeleton(context);
    final ex = widget.overview['settleExpiry'];
    if (ex is! Map) return _empty(context, '结算到期数据暂不可用');
    final days = [for (final v in (ex['days'] is List ? ex['days'] as List : const [])) _i(v) ?? 0];
    final week = _i(ex['week']) ?? 0;
    final total = _i(ex['total']) ?? 0;
    final today = _hDt(widget.overview['today']) ?? DateTime.now();
    var peak = 0;
    for (var i = 1; i < days.length; i++) {
      if (days[i] > days[peak]) peak = i;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpi(
          context,
          _count(week),
          '条',
          [
            const TextSpan(text: '结算明细 7 天内到期 '),
            if (week > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: ink.warnSoft, borderRadius: BorderRadius.circular(4)),
                  child: Text('临期', style: _sans(context, size: 9.5, color: _kCopper)),
                ),
              ),
          ],
          total == 0
              ? [const TextSpan(text: '未来 30 天没有到期的结算明细')]
              : [
                  const TextSpan(text: '未来 30 天共 '),
                  _b(context, _count(total)),
                  const TextSpan(text: ' 条'),
                  if (days.isNotEmpty && days[peak] >= 3) ...[
                    TextSpan(text: ' · ${_hMd(today.add(Duration(days: peak)))} 集中 '),
                    _b(context, '${days[peak]}'),
                    const TextSpan(text: ' 条'),
                  ],
                ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenExpiring,
            child: CustomPaint(
              size: Size.infinite,
              painter: _ExpiryDotsPainter(days: days, week: week, today: today, ink: ink),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 画法 ──

/// 阶梯爬坡：档位台阶底色 + 门槛线、真实锚点折线、跨档点、预测锥与到档区间、今天竖线。
class _TierClimbPainter extends CustomPainter {
  _TierClimbPainter({required this.rule, required this.ink, required this.pad, this.scrub});

  final _TierRule rule;
  final _HeroInk ink;
  final EdgeInsets pad;
  final double? scrub;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rule;
    final start = r.start, end = r.end, asOf = r.asOf;
    final plot = Rect.fromLTRB(pad.left, pad.top, size.width - pad.right, size.height - pad.bottom);
    if (start == null || end == null || asOf == null || plot.width <= 0 || plot.height <= 0) return;
    final span = math.max(1, end.difference(start).inMinutes).toDouble();
    double fx(DateTime t) => plot.left + (t.difference(start).inMinutes / span).clamp(0.0, 1.0) * plot.width;
    // 纵轴只放到「下一档」（下下档离得近就一并画），不被最高档压扁；更高的档在右上角注明。
    final top = r.tiers.isEmpty ? 0.0 : r.tiers.last.$1;
    var ymax = math.max(r.stat * 1.15, (r.next ?? 0) * 1.18);
    if (r.next != null && r.level + 1 < r.tiers.length) {
      final above = r.tiers[r.level + 1].$1;
      if (above <= r.next! * 1.6) ymax = math.max(ymax, above * 1.08);
    }
    // 预测期末的上界也纳入纵轴，让预测线和区间完整显示在图内。
    final forecastDays = math.max(0, end.difference(asOf).inMinutes) / 1440;
    if (!r.full && r.rate > 0 && forecastDays > 0) {
      ymax = math.max(ymax, (r.stat + forecastDays * r.rate * 1.3) * 1.08);
    }
    if (r.full) ymax = math.max(ymax, top * 1.12);
    if (ymax <= 0) ymax = 1;
    double fy(double v) => plot.bottom - v / ymax * plot.height;

    // 台阶底色：越高的档越深。
    for (var i = 0; i < r.tiers.length; i++) {
      final from = r.tiers[i].$1;
      final to = i + 1 < r.tiers.length ? r.tiers[i + 1].$1 : ymax;
      if (from >= ymax) break;
      if (i == 0) continue;
      canvas.drawRect(
        Rect.fromLTRB(plot.left, fy(math.min(to, ymax)), plot.right, fy(from)),
        Paint()..color = ink.purple.withValues(alpha: 0.03 * i),
      );
    }
    // 门槛线与档位标签（右侧）。
    final edge = Paint()
      ..color = ink.edge
      ..strokeWidth = 0.8;
    final labelStyle = ink.sans.copyWith(fontSize: 8.5);
    var lastLabelY = double.infinity;
    for (var i = 0; i < r.tiers.length; i++) {
      final (min, rate) = r.tiers[i];
      if (min > ymax) break;
      final y = fy(min);
      if (min > 0) canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), edge);
      final ly = math.min(y - 5.5, plot.bottom - 11);
      if (lastLabelY - ly < 10) continue;
      lastLabelY = ly;
      final cur = i + 1 == r.level;
      _paintText(
        canvas,
        '${i + 1}档 $rate',
        labelStyle.copyWith(color: cur ? ink.deep : (i < r.level ? ink.ink2 : ink.mute), fontWeight: cur ? FontWeight.w600 : FontWeight.w400),
        Offset(plot.right + 5, ly),
      );
    }

    final hidden = r.tiers.where((t) => t.$1 > ymax).length;
    if (hidden > 0) {
      _paintText(canvas, '↑ 更高 $hidden 档', labelStyle.copyWith(color: ink.mute), Offset(plot.right + 5, plot.top - 12));
    }

    // 未来区间淡一层。
    final xNow = fx(asOf);
    canvas.drawRect(Rect.fromLTRB(xNow, plot.top, plot.right, plot.bottom), Paint()..color = ink.card.withValues(alpha: 0.35));

    // 预测锥（裁到绘图区内）。
    final daysLeft = math.max(0, end.difference(asOf).inMinutes) / 1440;
    if (!r.full && r.rate > 0 && daysLeft > 0) {
      canvas.save();
      canvas.clipRect(plot);
      final y0 = fy(r.stat);
      final cone = Path()
        ..moveTo(xNow, y0)
        ..lineTo(plot.right, fy(r.stat + daysLeft * r.rate * 1.3))
        ..lineTo(plot.right, fy(r.stat + daysLeft * r.rate * 0.7))
        ..close();
      canvas.drawPath(cone, Paint()..color = ink.purple.withValues(alpha: 0.12));
      _dashLine(
        canvas,
        Offset(xNow, y0),
        Offset(plot.right, fy(r.stat + daysLeft * r.rate)),
        Paint()
          ..color = ink.purple
          ..strokeWidth = 1.4,
      );
      canvas.restore();
    }

    // 实际爬坡：锚点折线 + 渐变面积。
    final pts = [for (final (t, v) in r.anchors) Offset(fx(t), fy(v))];
    if (pts.length >= 2) {
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      final area = Path.from(line)
        ..lineTo(pts.last.dx, plot.bottom)
        ..lineTo(pts.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ink.purple.withValues(alpha: 0.26), ink.purple.withValues(alpha: 0)],
          ).createShader(plot),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = ink.purple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      // 跨档点：两端以外的锚点；最近一次跨档写日期。
      for (var i = 1; i < pts.length - 1; i++) {
        canvas.drawCircle(pts[i], 5, Paint()..color = ink.card);
        canvas.drawCircle(pts[i], 3.5, Paint()..color = ink.purple);
        if (i == pts.length - 2) {
          final text = '${_hMd(r.anchors[i].$1)} 跨档';
          final w = _textWidth(text, labelStyle);
          final left = pts[i].dx - 6 - w >= plot.left;
          _paintText(canvas, text, labelStyle, Offset(left ? pts[i].dx - 6 : pts[i].dx + 6, pts[i].dy - 15),
              align: left ? TextAlign.right : TextAlign.left, halo: ink.card);
        }
      }
    }

    // 到档日期：区间粗线 + 空心点 + 「预计 MM/dd」；到不了写明。
    final next = r.next;
    if (!r.full && next != null && next <= ymax) {
      final yn = fy(next);
      final eta = r.eta;
      if (r.reachable && eta != null) {
        final early = r.etaEarly ?? eta, late = r.etaLate ?? eta;
        canvas.drawLine(
          Offset(fx(early), yn),
          Offset(fx(late.isAfter(end) ? end : late), yn),
          Paint()
            ..color = ink.purple.withValues(alpha: 0.25)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
        final xe = fx(eta);
        canvas.drawCircle(Offset(xe, yn), 3.6, Paint()..color = ink.card);
        canvas.drawCircle(
          Offset(xe, yn),
          3.6,
          Paint()
            ..color = ink.purple
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final text = '预计 ${_hMd(eta)} 到达下一档';
        final w = _textWidth(text, labelStyle);
        final cx = plot.width <= w ? xe : math.min(math.max(xe, plot.left + w / 2), plot.right - w / 2);
        _paintText(canvas, text, labelStyle.copyWith(color: ink.deep, fontWeight: FontWeight.w600), Offset(cx, yn - 16),
            align: TextAlign.center, halo: ink.card);
      } else {
        _paintText(canvas, '本期到不了下一档', labelStyle.copyWith(color: ink.mute), Offset(plot.right - 4, yn - 14),
            align: TextAlign.right, halo: ink.card);
      }
    }

    // 今天：竖线 + 当前点。
    canvas.drawLine(
      Offset(xNow, plot.top),
      Offset(xNow, plot.bottom),
      Paint()
        ..color = ink.ink2.withValues(alpha: 0.35)
        ..strokeWidth = 0.8,
    );
    canvas.drawCircle(Offset(xNow, fy(r.stat)), 3, Paint()..color = ink.purple);

    // 横轴。
    canvas.drawLine(Offset(plot.left, plot.bottom), Offset(plot.right, plot.bottom), edge);
    final ay = plot.bottom + 3;
    _paintText(canvas, _hMd(start), ink.mono, Offset(plot.left, ay));
    _paintText(canvas, _hMd(end), ink.mono, Offset(plot.right, ay), align: TextAlign.right);
    if (xNow - plot.left > 40 && plot.right - xNow > 40) {
      _paintText(canvas, '今天', ink.sans.copyWith(color: ink.ink2), Offset(xNow, ay), align: TextAlign.center);
    }

    // 长按读数。
    final s = scrub;
    if (s != null) {
      final t = start.add(Duration(minutes: (span * s).round()));
      final x = fx(t);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = ink.ink.withValues(alpha: 0.28)
          ..strokeWidth = 1,
      );
      final v = r.valueAt(t).$1;
      if (v <= ymax) {
        canvas.drawCircle(Offset(x, fy(v)), 3.6, Paint()..color = ink.card);
        canvas.drawCircle(
          Offset(x, fy(v)),
          3.6,
          Paint()
            ..color = ink.purple
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TierClimbPainter old) => old.rule.m != rule.m || old.scrub != scrub || old.ink.purple != ink.purple || old.ink.card != ink.card;
}

/// 跨档进度的一条：一段 = 一档，已到的段填满，正在爬的段按进度填，点 = 当前位置。
class _RaceTrackPainter extends CustomPainter {
  _RaceTrackPainter({
    required this.segments,
    required this.level,
    required this.frac,
    required this.full,
    required this.fill,
    required this.track,
  });

  final int segments;
  final int level;
  final double frac;
  final bool full;
  final Color fill, track;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0, th = 2.0;
    final y = (size.height - th) / 2;
    final segW = (size.width - gap * (segments - 1)) / segments;
    if (segW <= 0) return;
    for (var j = 0; j < segments; j++) {
      final x = j * (segW + gap);
      final rr = Radius.circular(th / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, segW, th), rr), Paint()..color = track);
      final f = full || j < level ? 1.0 : (j == level ? frac : 0.0);
      if (f > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, math.max(th, segW * f), th), rr), Paint()..color = fill);
      }
    }

  }

  @override
  bool shouldRepaint(_RaceTrackPainter old) =>
      old.level != level || old.frac != frac || old.full != full || old.fill != fill || old.segments != segments || old.track != track;
}

/// 推送示波器：上方每根针 = 一次推送（高 = 耗时，色 = 类型 / 失败），下方镜像 = 每 10 分钟结算回传批次。
class _PushScopePainter extends CustomPainter {
  _PushScopePainter({required this.events, required this.returns, required this.nowMinute, required this.ink});

  final List<(double, Color, int?)> events; // (分钟, 颜色, 耗时 ms)
  final List<(int, bool)> returns; // (分钟, 是否异常)
  final double nowMinute;
  final _HeroInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    const mt = 4.0, mb = 14.0;
    final plot = Rect.fromLTRB(1, mt, size.width - 1, size.height - mb);
    if (plot.width <= 0 || plot.height <= 0) return;
    double fx(double m) => plot.left + (m / 1440).clamp(0.0, 1.0) * plot.width;
    final base = plot.top + plot.height * 0.62;
    final upH = base - plot.top - 4;
    final downH = plot.bottom - base - 3;
    final xNow = fx(nowMinute);

    final grid = Paint()
      ..color = ink.line
      ..strokeWidth = 0.8;
    for (final h in [6, 12, 18]) {
      canvas.drawLine(Offset(fx(h * 60.0), plot.top), Offset(fx(h * 60.0), plot.bottom), grid);
    }
    _hatch(canvas, Rect.fromLTRB(xNow, plot.top, plot.right, plot.bottom), ink.edge);

    // 回传：每 10 分钟一档，向下。
    final bins = List<int>.filled(144, 0);
    final bad = List<bool>.filled(144, false);
    for (final (m, abnormal) in returns) {
      final i = math.min(143, math.max(0, m ~/ 10));
      bins[i]++;
      if (abnormal) bad[i] = true;
    }
    final maxBin = bins.fold<int>(0, math.max);
    if (maxBin > 0) {
      final bw = math.max(1.2, plot.width / 144 - 0.6);
      for (var i = 0; i < 144; i++) {
        if (bins[i] == 0) continue;
        final h = math.max(1.0, bins[i] / maxBin * downH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(fx(i * 10.0), base + 2, bw, h), const Radius.circular(0.6)),
          Paint()..color = bad[i] ? ink.coral.withValues(alpha: 0.75) : ink.purple.withValues(alpha: 0.28),
        );
      }
    }
    canvas.drawLine(
      Offset(plot.left, base + 1),
      Offset(xNow, base + 1),
      Paint()
        ..color = ink.ink2.withValues(alpha: 0.3)
        ..strokeWidth = 0.8,
    );

    // 推送针。
    var maxCost = 1;
    for (final e in events) {
      if (e.$3 != null && e.$3! > maxCost) maxCost = e.$3!;
    }
    for (final (m, color, cost) in events) {
      final x = fx(m);
      final h = cost == null ? upH * 0.45 : (cost / maxCost).clamp(0.08, 1.0) * upH;
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base - h),
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(x, base - h), 3.8, Paint()..color = ink.card);
      canvas.drawCircle(Offset(x, base - h), 2.6, Paint()..color = color);
    }

    // 现在。
    canvas.drawLine(
      Offset(xNow, plot.top),
      Offset(xNow, plot.bottom),
      Paint()
        ..color = ink.purple
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(Offset(xNow, base + 1), 3, Paint()..color = ink.purple);

    final ay = plot.bottom + 2;
    for (final h in [0, 6, 12, 18, 24]) {
      _paintText(canvas, h.toString().padLeft(2, '0'), ink.mono, Offset(fx(h * 60.0), ay),
          align: h == 0 ? TextAlign.left : (h == 24 ? TextAlign.right : TextAlign.center));
    }
    if (plot.right - xNow > 64) {
      _paintText(canvas, '推送耗时 ↑', ink.sans.copyWith(color: ink.mute), Offset(plot.right - 2, plot.top + 1), align: TextAlign.right);
      _paintText(canvas, '回传批次 ↓', ink.sans.copyWith(color: ink.mute), Offset(plot.right - 2, plot.bottom - 13), align: TextAlign.right);
    }
  }

  @override
  bool shouldRepaint(_PushScopePainter old) =>
      old.events.length != events.length || old.returns.length != returns.length || old.nowMinute != nowMinute || old.ink.purple != ink.purple || old.ink.card != ink.card;
}

/// 到期点阵：一列 = 一天，一个点 = 一条（太多时一点代表多条），前 7 天用临期色。
class _ExpiryDotsPainter extends CustomPainter {
  _ExpiryDotsPainter({required this.days, required this.week, required this.today, required this.ink});

  final List<int> days;
  final int week;
  final DateTime today;
  final _HeroInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const mt = 15.0, mb = 14.0;
    final plot = Rect.fromLTRB(1, mt, size.width - 1, size.height - mb);
    final n = days.length;
    final cw = plot.width / n;
    final r = math.min(3.2, cw / 2 - 1).clamp(1.2, 3.2).toDouble();
    final step = r * 2 + 2;
    final capacity = math.max(1, ((plot.height - 2) / step).floor());
    final maxV = days.fold<int>(0, math.max);
    final per = math.max(1, (maxV / capacity).ceil());

    final band = Rect.fromLTRB(plot.left - 1, 0, plot.left + cw * math.min(7, n), plot.bottom + 2);
    canvas.drawRRect(RRect.fromRectAndRadius(band, const Radius.circular(6)), Paint()..color = ink.warnSoft);
    _paintText(canvas, '7 天内 $week 条', ink.sans.copyWith(color: ink.warnInk, fontWeight: FontWeight.w600), Offset(band.left + 5, 2));
    if (per > 1) {
      _paintText(canvas, '每点 $per 条', ink.sans.copyWith(color: ink.mute), Offset(plot.right, 2), align: TextAlign.right);
    }

    final baseY = plot.bottom - r;
    canvas.drawLine(
      Offset(plot.left, plot.bottom + 1),
      Offset(plot.right, plot.bottom + 1),
      Paint()
        ..color = ink.edge
        ..strokeWidth = 0.8,
    );
    for (var i = 0; i < n; i++) {
      final cx = plot.left + cw * i + cw / 2;
      final v = days[i];
      if (v == 0) {
        canvas.drawCircle(Offset(cx, baseY), 1, Paint()..color = ink.edge);
        continue;
      }
      final dots = (v / per).ceil();
      final color = i < 7 ? ink.warn : ink.purple.withValues(alpha: 0.45);
      for (var j = 0; j < dots; j++) {
        canvas.drawCircle(Offset(cx, baseY - j * step), r, Paint()..color = color);
      }
    }
    final ay = plot.bottom + 3;
    for (final i in [0, 7, 14, 21, 28]) {
      if (i >= n) break;
      _paintText(canvas, _hMd(today.add(Duration(days: i))), ink.mono, Offset(plot.left + cw * i + cw / 2, ay),
          align: i == 0 ? TextAlign.left : TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(_ExpiryDotsPainter old) =>
      old.week != week || old.today != today || old.ink.purple != ink.purple || !_sameInts(old.days, days);
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

// ═════════════════════════════ 阶梯 / 价格规则 ═════════════════════════════
//   资管的「阶梯价格」不在结算明细上：明细只记结算方式 3（按阶梯价格）和公式，比如「核销面值-门槛金额*阶梯价格」；
//   档位在价格规则里，经关联表挂到产品上（数据来自 business-go mobile.TierRules）：
//     · 折扣取值（rel 1）：公式里的「阶梯价格」就取这条规则当期命中档的比例；
//     · 参与核算（rel 2）：本产品的量计入这条规则的阶梯基数，但比例不从它取；
//     · 渠道产品还会带上货源供应商产品挂的规则（采购侧阶梯），以及推广商规则。

String _billingModelLabel(String v) => switch (v) {
  '1' => '阶梯计费',
  '2' => '时间区间折扣',
  '3' => '推广商分润',
  _ => '价格规则',
};

String _dimensionLabel(String v) => switch (v) {
  '1' => '按销售额',
  '2' => '按核销额',
  '3' => '按门槛金额',
  '4' => '按引流金额',
  _ => '',
};

String _calcModeLabel(String v) => switch (v) {
  '1' => '超额累进',
  '2' => '全额累进',
  _ => '',
};

String _calcModeNote(String v) => switch (v) {
  '1' => '超额累进：本期基数按档位切段，每一段只按所在档的比例算，再加总。',
  '2' => '全额累进：本期基数到了哪一档，整期基数全部按那一档的比例算。',
  _ => '',
};

String _relTypeLabel(String v) => switch (v) {
  '1' => '折扣取值',
  '2' => '参与核算',
  _ => '',
};

/// 账期：按月 / 按年，自然月 / 自定义区间（每月 N 日–M 日）/ 跨月。
String _cycleLabel(Map<String, dynamic> r) {
  final type = switch (_s(r['cycleType'])) {
    '1' => '按月',
    '2' => '按年',
    _ => '',
  };
  final start = _s(r['cycleStartDay']), end = _s(r['cycleEndDay']);
  final calc = switch (_s(r['cycleCalcType'])) {
    '1' => '自然月',
    '2' => start.isEmpty ? '自定义区间' : '每期 $start 日–$end 日',
    '3' => '跨月',
    _ => '',
  };
  return [type, calc].where((e) => e.isNotEmpty).join(' · ');
}

/// 金额（元）：≥1 万写「3,000万」「12.5万」，否则千分位到元。
String _wan(Object? v) {
  final d = double.tryParse(_s(v));
  if (d == null) return '—';
  if (d.abs() >= 10000) {
    final w = d / 10000;
    final t = w == w.roundToDouble() ? _count(w.round()) : w.toStringAsFixed(w.abs() >= 100 ? 0 : 2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$t万';
  }
  if (d == d.roundToDouble()) return _count(d.round());
  return d.toStringAsFixed(2);
}

/// 「2026-03-29 00:00:00」→「03-29」；取不到 →「—」。
String _md(Object? v) {
  final s = _s(v);
  return s.length >= 10 ? s.substring(5, 10) : '—';
}

/// 比例：资管存小数（0.0150 = 1.5%）。
String _rate(Object? v) {
  final d = double.tryParse(_s(v));
  if (d == null) return '—';
  final p = d * 100;
  var t = p.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$t%';
}

/// 档位区间：「0 ≤ 基数 < 3,000万」/「≥ 5,000万」。
String _tierRange(Map<String, dynamic> t, String unit) {
  final hasMin = _s(t['minValue']).isNotEmpty;
  final hasMax = _s(t['maxValue']).isNotEmpty;
  final lo = _s(t['isMinInclusive']) == '0' ? '<' : '≤';
  final hi = _s(t['isMaxInclusive']) == '1' ? '≤' : '<';
  final fmt = unit == '人' ? (Object? v) => '${_count(_i(v))}人' : _wan;
  if (hasMin && hasMax) return '${fmt(t['minValue'])} $lo 基数 $hi ${fmt(t['maxValue'])}';
  if (hasMin) return '${lo == '≤' ? '≥' : '>'} ${fmt(t['minValue'])}';
  if (hasMax) return '$hi ${fmt(t['maxValue'])}';
  return '不限';
}

/// 一张三列小表：表头 + 行；[hit] 为高亮行下标。
Widget _miniTable(BuildContext context, List<String> head, List<List<String>> rows, {int? hit, String hitTag = ''}) {
  Widget cell(String text, {bool headRow = false, bool on = false, TextAlign align = TextAlign.left, int flex = 1}) => Expanded(
    flex: flex,
    child: Text(
      text,
      textAlign: align,
      style: headRow
          ? _sans(context, size: 10, color: _kMute)
          : LhTypography.mono(context: context, size: 11, weight: on ? FontWeight.w700 : FontWeight.w500, color: _fg(context, on ? _kDeep : _kInk)),
    ),
  );
  return Container(
    decoration: BoxDecoration(color: _bg(context, _kPanel), borderRadius: BorderRadius.circular(10)),
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
    child: Column(
      children: [
        Row(children: [
          cell(head[0], headRow: true),
          cell(head[1], headRow: true, flex: 4),
          cell(head[2], headRow: true, align: TextAlign.right, flex: 2),
        ]),
        const SizedBox(height: 4),
        for (var i = 0; i < rows.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            decoration: i == hit ? BoxDecoration(color: _bg(context, _kLavender), borderRadius: BorderRadius.circular(6)) : null,
            child: Row(children: [
              cell(rows[i][0], on: i == hit),
              cell(rows[i][1], on: i == hit, flex: 4),
              cell(i == hit && hitTag.isNotEmpty ? '${rows[i][2]} ◂' : rows[i][2], on: i == hit, align: TextAlign.right, flex: 2),
            ]),
          ),
        if (hit != null && hitTag.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Align(alignment: Alignment.centerLeft, child: Text('◂ $hitTag', style: _sans(context, size: 10, color: _kDeep))),
          ),
      ],
    ),
  );
}

/// 规则挂在哪：本产品 / 本渠道产品 / 货源供应商产品（采购侧）。
String _ruleVia(Map<String, dynamic> r) {
  final raw = r['relTypes'] is List ? (r['relTypes'] as List) : const <Object?>[];
  final types = raw.map((t) => _relTypeLabel(_s(t))).where((e) => e.isNotEmpty).toSet().join('、');
  final rel = types.isEmpty ? '' : ' · $types';
  switch (_s(r['via'])) {
    case 'source':
      final ps = _list(r['products']);
      final names = ps.map((p) => [_s(p['supplier']), _s(p['name'])].where((e) => e.isNotEmpty).join(' · ')).toSet().toList();
      return '采购侧 · 货源 ${names.isEmpty ? '供应商产品' : names.first}${names.length > 1 ? ' 等 ${names.length} 个' : ''}$rel';
    case 'channel':
      return '挂在本渠道产品$rel';
    default:
      return '挂在本产品$rel';
  }
}

/// 一条价格规则的完整展示：类型 / 维度 / 累进方式 / 账期 / 门槛 / 档位表（命中档高亮）/ 最近一期 / 有效期。
Widget _tierRuleCard(BuildContext context, Map<String, dynamic> r) {
  final model = _s(r['billingModelType']);
  final status = _s(r['status']);
  final tiers = _list(r['tiers']);
  final segments = _list(r['timeDiscounts']);
  final promoters = _list(r['promoterDetails']);
  final latest = _map(r['latest']);
  final hitLevel = _s(latest['tierLevel']);
  final threshold = double.tryParse(_s(r['tierThresholdAmount'])) ?? 0;
  final tags = [_billingModelLabel(model), _dimensionLabel(_s(r['dimensionType'])), _calcModeLabel(_s(r['calcMode'])), _cycleLabel(r)]
      .where((e) => e.isNotEmpty)
      .join(' · ');
  final start = _s(r['effectiveStartTime']), end = _s(r['effectiveEndTime']);
  int? hit;
  for (var i = 0; i < tiers.length; i++) {
    if (hitLevel.isNotEmpty && _s(tiers[i]['tierLevel']) == hitLevel) hit = i;
  }
  final latestText = latest.isEmpty
      ? ''
      : [
          '最近一期${_s(latest['periodNo']).isEmpty ? '' : '（第 ${_s(latest['periodNo'])} 期）'} ${_md(latest['periodStart'])}–${_md(latest['periodEnd'])}',
          '基数 ${_wan(latest['statAmount'])}',
          if (hitLevel.isNotEmpty) '命中第 $hitLevel 档 ${_rate(latest['discountRate'])}',
          if (_s(latest['rebateAmount']).isNotEmpty) '返利 ${_wan(latest['rebateAmount'])}',
        ].join(' · ');
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
            Expanded(child: Text(_s(r['ruleName']).isEmpty ? '价格规则' : _s(r['ruleName']), style: _sans(context, size: 13, weight: FontWeight.w700, height: 1.35))),
            const SizedBox(width: 6),
            _tag(context, status == '1' ? '启用' : (status == '0' ? '停用' : (status.isEmpty ? '—' : status)), status == '1' ? _Tone.purple : _Tone.grey),
          ],
        ),
        const SizedBox(height: 3),
        Text(tags, style: _sans(context, size: 11, weight: FontWeight.w600, color: _kDeep)),
        const SizedBox(height: 2),
        Text(_ruleVia(r), style: _sans(context, size: 10.5, color: _kMute)),
        if (threshold > 0) ...[
          const SizedBox(height: 2),
          Text('阶梯门槛 ${_wan(threshold)}：基数达到门槛才开始计', style: _sans(context, size: 10.5, color: _kInk2)),
        ],
        if (tiers.isNotEmpty) ...[
          const SizedBox(height: 8),
          _miniTable(
            context,
            const ['档位', '本期基数（元）', '比例'],
            [for (final t in tiers) ['${_s(t['tierLevel'])} 档', _tierRange(t, '元'), _rate(t['discountRate'])]],
            hit: hit,
            hitTag: hit == null ? '' : '最近一期命中',
          ),
          if (_calcModeNote(_s(r['calcMode'])).isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(_calcModeNote(_s(r['calcMode'])), style: _sans(context, size: 10.5, color: _kMute, height: 1.5)),
          ],
        ] else if (model == '1') ...[
          const SizedBox(height: 6),
          Text('这条阶梯规则没有配置档位', style: _sans(context, size: 11, color: _kCoral)),
        ],
        if (segments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _miniTable(
            context,
            const ['#', '时间段', '折扣'],
            [
              for (final t in segments)
                [
                  _s(t['sortNo']).isEmpty ? '·' : _s(t['sortNo']),
                  [_s(t['segmentName']), '${_date(t['startTime'])}–${_date(t['endTime'])}'].where((e) => e.isNotEmpty).join(' '),
                  _rate(t['discountRate']),
                ],
            ],
          ),
        ],
        for (final d in promoters) ..._promoterRows(context, d),
        if (latestText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(latestText, style: LhTypography.mono(context: context, size: 10.5, color: _fg(context, _kInk2))),
        ],
        const SizedBox(height: 4),
        Text(
          '有效期 ${start.isEmpty ? '—' : _date(start)} → ${end.isEmpty ? '长期' : _date(end)}${_s(r['ruleCode']).isEmpty ? '' : ' · ${_s(r['ruleCode'])}'}',
          style: LhTypography.mono(context: context, size: 10, color: _fg(context, _kMute)),
        ),
      ],
    ),
  );
}

/// 推广商分润明细：连续月策略按月序写，新客阶梯比例成表。
List<Widget> _promoterRows(BuildContext context, Map<String, dynamic> d) {
  final policy = _s(d['policyType']);
  final from = _s(d['streakMonth']), to = _s(d['monthEnd']);
  final months = from.isEmpty ? '' : (to.isEmpty ? '第 $from 月起' : '第 $from–$to 月');
  final value = switch (policy) {
    'FIXED_AMOUNT' => '固定 ${_yuan(d['fixedAmount'])}',
    'FIXED_PERCENTAGE' => '固定 ${_plain(d['fixedPercentage'])}%',
    _ => switch (_s(d['calcType'])) {
      'amount' => '每户 ${_yuan(d['calcValue'])}',
      'percentage' => '分润 ${_plain(d['calcValue'])}%',
      'tier_ratio' => '按新客阶梯比例',
      _ => _s(d['calcType']),
    },
  };
  final tiers = _list(d['tiers']);
  return [
    const SizedBox(height: 6),
    Text(
      [months.isEmpty ? '推广商分润' : months, value, if (_s(d['stopProfitMonth']).isNotEmpty) '第 ${_s(d['stopProfitMonth'])} 月停止'].join(' · '),
      style: _sans(context, size: 11, weight: FontWeight.w600, color: _kInk2),
    ),
    if (tiers.isNotEmpty) ...[
      const SizedBox(height: 4),
      _miniTable(
        context,
        const ['档位', '本月新客数', '分润比例'],
        [
          for (var i = 0; i < tiers.length; i++)
            [
              '${i + 1} 档',
              _s(tiers[i]['maxNewCustomers']).isEmpty
                  ? '≥ ${_count(_i(tiers[i]['minNewCustomers']))} 人'
                  : '${_count(_i(tiers[i]['minNewCustomers']))}–${_count(_i(tiers[i]['maxNewCustomers']))} 人',
              '${_plain(tiers[i]['profitRatio'])}%',
            ],
        ],
      ),
    ],
  ];
}

/// 结算方式 3（按阶梯价格）的规则卡里，直接把「阶梯价格」取自哪条规则、各档比例摆出来。
/// [tierRules] 里优先取挂在本产品 / 本渠道产品、关联类型含「折扣取值」的规则。
bool _isSettlementPriceSource(Map<String, dynamic> r) =>
    _s(r['via']) != 'source' && _list(r['tiers']).isNotEmpty &&
    r['relTypes'] is List && (r['relTypes'] as List).map((e) => _s(e)).contains('1');

Widget _tierPriceInline(BuildContext context, Map<String, dynamic> item, List<Map<String, dynamic>> tierRules) {
  final own = tierRules.where(_isSettlementPriceSource).toList();
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(own.length > 1 ? '本产品关联了多条折扣取值规则，需按资管配置核对适用规则' : '阶梯价格 · 折扣取值规则',
        style: _sans(context, size: 12, weight: FontWeight.w600, color: _kDeep)),
      const SizedBox(height: 6),
      if (own.isEmpty)
        Text('未找到本产品用于折扣取值的阶梯档位，请核对资管价格规则配置。', style: _sans(context, size: 11, color: _kCoral, height: 1.5))
      else
        _bizSpaced([for (final r in own) _tierRuleCard(context, r)]),
    ]),
  );
}

/// 「阶梯与价格规则」一节开头的说明：这个产品的阶梯在哪一侧、为什么渠道侧可能没有阶梯。
String _tierIntro(String side, List<Map<String, dynamic>> items, List<Map<String, dynamic>> tierRules) {
  final tierItems = items.where((e) => _s(e['settleMethod']) == '3').length;
  final source = tierRules.where((r) => _s(r['via']) == 'source').length;
  final own = tierRules.length - source;
  if (side == 'supplier') {
    if (tierRules.isEmpty) {
      return tierItems > 0 ? '有 $tierItems 条结算按阶梯价格，但本产品没有挂价格规则，阶梯价格取不到。' : '本产品按固定比例 / 单价结算，没有挂阶梯规则。';
    }
    return '本产品挂了 ${tierRules.length} 条价格规则。「折扣取值」= 结算公式里的阶梯价格取它；「参与核算」= 本产品的量计入它的阶梯基数。';
  }
  final parts = <String>[
    tierItems > 0 ? '渠道侧有 $tierItems 条结算按阶梯价格。' : '渠道侧结算是固定比例 / 单价，没有阶梯。',
    if (source > 0) '阶梯在采购侧：货源供应商产品挂了 $source 条价格规则（供应商按量返利，影响成本，不改变渠道侧结算）。',
    if (own > 0) '本渠道产品另挂了 $own 条规则（推广商分润等）。',
    if (tierRules.isEmpty) '货源供应商产品也没有挂阶梯规则。',
  ];
  return parts.join('');
}

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
  '3' => '阶梯价格',
  _ => label,
};

String _spStateLabel(String v) => switch (v) {
  'effective' => '供应商产品 可供货',
  'pending' => '供应商产品 待审核',
  'disabled' => '供应商产品 已停用',
  _ => '',
};

/// 结算段：条数 + 方式 + 到期；30 天内到期标铜色。
_ChainSeg _settleSeg(BuildContext context, Map<String, dynamic> p, String side, {bool usable = true}) {
  final n = _i(p['settlementCount']) ?? 0;
  final supplierMissing = side == 'channel' && _s(p['chainReason']) == 'supplierNoSettlement';
  final days = _daysUntil(p['settlementExpire']);
  final soon = days != null && days <= 30;
  final rule = _ruleShort(_s(p['settleMethodCode']), p['settlementRatio'], p['settlementUnitPrice'], _s(p['settleMethod']));
  return _ChainSeg(
    '结算',
    n > 0 ? '$n 条' : '未配置',
    sub: supplierMissing ? '供给侧结算待配置' : n > 0 ? [if (rule.isNotEmpty) rule, soon ? '$days 天到期' : _expireShort(p['settlementExpire'])].join(' · ') : (usable ? '审核生效且启用' : ''),
    tone: supplierMissing ? _SegTone.warn : n > 0 ? (soon ? _SegTone.warn : _SegTone.normal) : (usable ? _SegTone.bad : _SegTone.none),
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
  var hintColor = _kCopper;
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
    final suggested = _suggestedSubjects(p['counterparties']);
    body = _miniChain(context, [
      _ChainSeg(
        _legalLabel(kind),
        linked ? (_s(p['subjectName']).isEmpty ? '主体档案不可用' : _subjectDisplay(p['subjectName'])) : _unlinkedValue(p['counterparties']),
        // 渠道档案的 entity_name 是我方签约主体，不是渠道的主体，单独写清。
        sub: kind == 'channel' && _s(p['entityName']).isNotEmpty
            ? '我方签约 ${_s(p['entityName'])}'
            : (!linked && suggested.isNotEmpty ? '建议 ${_subjectDisplay(suggested.first['subjectName'])}' : ''),
        tone: linked ? _SegTone.normal : _SegTone.warn,
        onTap: linked
            ? () => _openBizSubject(context, _s(p['subjectId']), _s(p['subjectName']))
            : (suggested.isEmpty ? null : () => _openBizSubject(context, _s(suggested.first['subjectId']), _s(suggested.first['subjectName']))),
      ),
      _ChainSeg(
        '产品',
        '${_count(products)} 个',
        sub: '已审核 ${_count(effective)}$extra',
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
    if (!linked) {
      hint = _unlinkedHint(_legalLabel(kind), p['counterparties']);
      hintColor = suggested.isNotEmpty ? _kCopper : _kChainGrey;
    }
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
        if (hint != null) _chainHint(context, hint, hintColor),
      ],
    ),
  );
}

/// 结算卡：产品名 / 首条规则 / 签约双方 + 迷你链（渠道或供应商主体 › 渠道或供应商 › 产品）；点卡片进结算详情。
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
  final counterparty = _s(p['settlementCounterparty']);
  final (matchText, matchTone) = switch (match) {
    'match' => ('对方一致', _SegTone.normal),
    'mismatch' => ('对方不一致', _SegTone.bad),
    'unlinked' => ('$partnerLabel主体待补', _SegTone.warn),
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
    hint = '规则对方「$counterparty」与$partnerLabel主体「$subjectName」不是同一家';
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
                  if (our.isNotEmpty || counterparty.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '签约双方 · 我方 ${our.isEmpty ? '—' : _subjectDisplay(our)} ⇄ 对方 ${counterparty.isEmpty ? '—' : _subjectDisplay(counterparty)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(context, size: 10.5, color: _kInk2),
                    ),
                  ],
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
                    : (soon ? _tag(context, (days ?? 0) <= 0 ? '今天到期' : '$days 天到期', _Tone.copper) : _tag(context, '执行中', _Tone.purple)),
              ],
            ),
          ],
        ),
        _miniChain(context, [
          // 这一格是渠道 / 供应商档案上的主体（应与规则「对方」是同一家），不是我方。
          _ChainSeg(
            '$partnerLabel主体',
            subjectName.isEmpty ? '待补' : _subjectDisplay(subjectName),
            sub: subjectName.isEmpty && counterparty.isNotEmpty ? '规则对方 ${_subjectDisplay(counterparty)}' : '',
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

/// 产品卡的迷你链（供应商主体 › 供应商 › 结算，渠道产品看首选货源的供应商）与问题提示。
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
        '供应商主体',
        subject.isEmpty ? '待补' : _subjectDisplay(subject),
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
        const _ChainSeg('供应商主体', '—', tone: _SegTone.none),
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
      '供应商主体',
      brk == 0 ? '—' : (subject.isEmpty ? '待补' : _subjectDisplay(subject)),
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
  // 直接说卡在哪一侧、差什么，不用「一端未可售」这类内部说法。
  final why = switch (reason) {
    'noSource' => '未连接货源：还没有配置供应商产品',
    'sourceBroken' => '货源失效：指向的供应商产品已删除',
    'channelPending' => '卡在渠道侧：渠道产品${_submitStatus(_s(p['submitStatus'])).$1}',
    'channelDisabled' => '卡在渠道侧：渠道产品${_productStatus('channel', _s(p['status']))}',
    'supplierNotEffective' => spState == 'disabled' ? '卡在供应商侧：供应商产品已停用' : '卡在供应商侧：供应商产品待审核',
    'noSettlement' => '渠道侧未配结算：还没有渠道侧结算规则',
    'supplierNoSettlement' => '供给侧未配结算：没有审核生效且启用的关联货源配置供应商侧结算规则',
    _ => segName,
  };
  if (brk >= 0) {
    // 颜色按灯塔的状态语言：铜 = 进行中，灰 = 停用 / 还没有，珊瑚 = 坏了。
    // 「待审核」是正常流程中的状态，链上那一格已经用铜色写了，这里不再重复、也不标红。
    final pending = reason == 'channelPending' || (reason == 'supplierNotEffective' && spState != 'disabled');
    if (pending) return (segs, null, _kInk);
    final color = switch (reason) {
      'sourceBroken' => _kCoral,
      'noSettlement' || 'supplierNoSettlement' => _kCopper,
      _ => _kChainGrey,
    };
    return (segs, why, color);
  }
  final days = _daysUntil(p['settlementExpire']);
  if (days != null && days <= 30) return (segs, '已贯通，结算规则 $days 天后到期', _kCopper);
  return (segs, null, _kInk);
}

/// Decimal-string IDs supplied by Lighthouse, never approximate a large numeric ID.
List<String> lighthouseLinkedRuleKeys(Object? discount) {
  final d = _map(discount);
  final keys = d['ruleKeys'];
  if (keys is List) return keys.map(_s).where((k) => k.isNotEmpty).toSet().toList();
  final id = _i(d['ruleId']);
  return id != null && id > 0 && id <= 9007199254740991 ? ['$id'] : const [];
}

List<String> lighthouseRuleKeysForRow(Map<String, dynamic> row) {
  final keys = row['linkedRuleKeys'];
  return keys is List ? keys.map(_s).where((k) => k.isNotEmpty).toSet().toList() : lighthouseLinkedRuleKeys(row['discount']);
}

/// A pushed route keeps the originating ledger's filters and scroll position intact.
class LighthouseLinkedRulesPage extends StatefulWidget {
  const LighthouseLinkedRulesPage({super.key, required this.service, required this.ruleKeys});
  final LighthouseService service;
  final List<String> ruleKeys;
  @override
  State<LighthouseLinkedRulesPage> createState() => _LighthouseLinkedRulesState();
}

class _LighthouseLinkedRulesState extends State<LighthouseLinkedRulesPage> {
  late final Future<Map<String, dynamic>> _overview = widget.service.fetchBizOverview();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关联阶梯规则')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _overview,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(_errText(snapshot.error!)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rules = _list(_map(snapshot.data!['tierBoard'])['rules'])
            .where((r) => widget.ruleKeys.contains(_s(r['ruleId']))).toList();
        if (rules.isEmpty) return const Center(child: Text('该规则暂无本期阶梯计算记录，无法展示本期走势。'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('显示账表记录明确关联的规则；规则周期独立于账表日期。', style: _sans(context, size: 12, color: _kMute)),
          const SizedBox(height: 12),
          _BizPulseHero(service: widget.service, ruleOnly: true, initialPage: 1, overview: {'tierBoard': {'rules': rules, 'total': rules.length, 'periodCross': rules.where((r) => r['reachable'] == true).length, 'weekCross': rules.where((m) { final r = _TierRule(m); final a = r.asOf; final e = r.eta; return r.reachable && a != null && e != null && e.isBefore(DateTime(a.year, a.month, a.day).add(Duration(days: 8 - a.weekday))); }).length}},
            loading: false, onOpenPush: () {}, onOpenExpiring: () {}),
        ]);
      },
    ),
  );
}

class LighthouseRuleLedgerPage extends StatefulWidget {
  const LighthouseRuleLedgerPage({super.key, required this.service, required this.rule});
  final LighthouseService service;
  final Map<String, dynamic> rule;
  @override
  State<LighthouseRuleLedgerPage> createState() => _LighthouseRuleLedgerState();
}

class _LighthouseRuleLedgerState extends State<LighthouseRuleLedgerPage> {
  String _period = 'rule';
  late DateTime _anchor = _hDt(widget.rule['asOf']) ?? DateTime.now();
  List<Map<String, dynamic>> _scopes = [];
  final Map<String, Map<String, dynamic>> _details = {};
  bool _loading = true;
  String? _error;
  int _seq = 0;
  @override
  void initState() { super.initState(); _load(resolve: true); }

  Future<void> _load({bool resolve = false}) async {
    final seq = ++_seq;
    setState(() { _loading = true; _error = null; });
    try {
      final start = _hDt(widget.rule['periodStart']);
      final end = _hDt(widget.rule['periodEnd']);
      final asOf = _hDt(widget.rule['asOf']);
      if (start == null || end == null || asOf == null) throw Exception('规则缺少统计周期或数据日期，暂不能关联账表。');
      final cutoff = asOf.isBefore(end) ? asOf : end;
      if (resolve) {
        final data = await widget.service.fetchDimension(tab: 'supply', period: 'day', startDate: start, endDate: cutoff);
        if (!mounted || seq != _seq) return;
        _scopes = _list(data['rows']).where((r) => lighthouseRuleKeysForRow(r).contains(_s(widget.rule['ruleId']))).toList();
      }
      final details = <String, Map<String, dynamic>>{};
      for (final scope in _scopes) {
        final name = _s(scope['name']);
        final group = _s(scope['group']);
        final key = group.isEmpty ? name : '$name::$group';
        final data = await widget.service.fetchDetail(tab: 'supply', key: key,
          period: _period == 'rule' ? 'day' : _period,
          date: _period == 'rule' ? null : _date(_anchor.toIso8601String()),
          startDate: _period == 'rule' ? start : null, endDate: _period == 'rule' ? cutoff : null);
        if (!mounted || seq != _seq) return;
        details[key] = _map(data['detail']);
      }
      if (!mounted || seq != _seq) return;
      setState(() { _details..clear()..addAll(details); _loading = false; });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() { _error = _errText(e); _loading = false; });
    }
  }

  Widget _ledger(BuildContext context, String key, Map<String, dynamic> data) {
    final rows = _list(data['supplierCode']);
    final products = rows.isEmpty ? _list(data['productName']) : rows;
    return Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14), decoration: _cardDeco(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(key.replaceAll('::', ' · '), style: _sans(context, size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final (field, label) in const [('sales', '销售额'), ('revenue', '收入'), ('totalCost', '成本合计'), ('profit', '利润')])
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            Expanded(child: Text(label, style: _sans(context, size: 12, color: _kInk2))), Text(_yuan(data[field]), style: _num(context, size: 14)),
          ])),
        const SizedBox(height: 8),
        Text('供给下的产品明细（供给全量范围）', style: _sans(context, size: 12, weight: FontWeight.w600)),
        if (products.isEmpty) Text('所选期间没有产品明细', style: _sans(context, size: 12, color: _kMute)),
        for (final p in products) ListTile(contentPadding: EdgeInsets.zero,
          title: Text(_s(p['name']), style: _sans(context, size: 12)),
          subtitle: Text('销售 ${_yuan(p['sales'])} · 利润 ${_yuan(p['profit'])}', style: _sans(context, size: 11, color: _kMute))),
        TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LighthouseLinkedRulesPage(
          service: widget.service, ruleKeys: [_s(widget.rule['ruleId'])]))), child: const Text('查看关联阶梯规则')),
      ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关联日月年表')),
    body: RefreshIndicator(onRefresh: () => _load(resolve: true), child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        Text(_s(widget.rule['name']), style: _sans(context, size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('规则周期：${_date(widget.rule['periodStart'])} 至 ${_date(widget.rule['periodEnd'])}\n规则数据截至：${_date(widget.rule['asOf'])}', style: _sans(context, size: 12, color: _kInk2)),
        const SizedBox(height: 8),
        Text('按账表计算记录中的规则ID关联供给。下方为关联供给的业务汇总及产品明细，并非本规则参与产品合计，不能直接作为跨档基数。', style: _sans(context, size: 11, color: _kCopper, height: 1.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final (value, label) in const [('rule', '规则本期'), ('day', '日表'), ('month', '月表'), ('year', '年表')])
          ChoiceChip(label: Text(label), selected: _period == value, onSelected: (_) { setState(() => _period = value); _load(); })]),
        if (_period == 'rule') Text('账表查询至规则数据截至日，不查询未来日期。', style: _sans(context, size: 11, color: _kMute))
        else TextButton(onPressed: () async {
          final picked = await showDatePicker(context: context, initialDate: _anchor, firstDate: DateTime(2000), lastDate: DateTime.now());
          if (picked == null || !mounted) return;
          setState(() => _anchor = picked); _load();
        }, child: Text(_period == 'year' ? '${_anchor.year} 年 · 选择日期' : _period == 'month' ? '${_anchor.year}-${_anchor.month} · 选择日期' : '${_date(_anchor.toIso8601String())} · 选择日期')),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_error != null) _inlineError(context, _error!, () => _load(resolve: true))
        else if (_scopes.isEmpty) Text('暂无明确的规则ID关联。可能是所选周期没有计算记录或映射尚未建立；不会按名称猜测匹配。', style: _sans(context, size: 12, color: _kMute))
        else ...[for (final entry in _details.entries) _ledger(context, entry.key, entry.value)],
      ],
    )),
  );
}
