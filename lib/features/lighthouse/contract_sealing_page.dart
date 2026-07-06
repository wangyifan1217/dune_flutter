// ═══════════════════════════════════════════════════════════════════════════
// contract_sealing_page.dart —— 灯塔 · 我的 · 合同用印
//
//   Drop-in 模块: 放到灯塔 App"我的"tab 里。沿用 lighthouse_theme.dart 的
//   LhColors / LhTypography (assumes 已导入)。视觉语言严格对齐 v3.7 编辑室:
//     · 暖 cream 3-stop 卡片 (#FFFFFC → #FAF8F0 → #F2EFDF)
//     · 暖 hairline #DDD5C0 一贯到底
//     · copper 唯一 accent, 无填色 badge / pill / chip
//     · mono numerals, sans 名称字段
//     · 返回键: mono ‹ + sans '返回'
//
//   痛点覆盖 (来自 2026-07 合同经办人访谈):
//     · 编号自动生成 (系统内一次生成, 无手工重复)
//     · 起止日期强制校验 + 明确文案提示
//     · 状态时间线 (draft → approving → sealed → archived)
//     · 审批链可视, 每步谁 / 何时 / 意见清晰
//
//   使用方式:
//     import 'contract_sealing_page.dart';
//     ...
//     Navigator.of(context).push(MaterialPageRoute(
//       builder: (_) => const ContractSealingPage(),
//     ));
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'lighthouse_theme.dart'; // 假定同目录; 你可以调整路径

// ═══════════════════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════════════════

enum SealStatus {
  draft,         // 起草中 - 我写完但没提交
  approving,     // 审批中 - 已提交, 待审批人处理
  approved,      // 已通过, 待用印
  sealed,        // 已用印, 待归档 (合同外发签署中)
  archived,      // 已归档 (纸质件回收扫描完成)
  rejected,      // 已驳回
}

enum ApprovalAction { pending, approved, rejected, transferred }

class ApprovalStep {
  final String role;
  final String approver;
  final DateTime? at;
  final ApprovalAction action;
  final String? comment;
  const ApprovalStep({
    required this.role,
    required this.approver,
    this.at,
    this.action = ApprovalAction.pending,
    this.comment,
  });
}

/// 借阅记录 —— 每次借阅一份合同都产生一条
///   核心目的:
///     1. 产出带水印 PDF (借阅方仅供 XX 使用)
///     2. 审计追踪 (谁 / 何时 / 借哪份 / 有效期到何时)
///     3. 到期自动失效 (下载链接过期)
class BorrowRecord {
  final String id;              // e.g. JY-20260701-001
  final String borrowerUnit;    // 借阅单位 (水印动态字段)
  final String purpose;         // 借阅用途
  final String medium;          // '电子件' / '纸质件'
  final DateTime borrowedAt;
  final DateTime expiresAt;     // 电子件有效期
  final String applicant;       // 经办人
  final int downloadCount;      // 下载次数 (审计)

  const BorrowRecord({
    required this.id,
    required this.borrowerUnit,
    required this.purpose,
    required this.medium,
    required this.borrowedAt,
    required this.expiresAt,
    required this.applicant,
    this.downloadCount = 0,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class SealApplication {
  final String id;              // 系统编号 (自动生成, e.g. YY-20260701-001)
  final String partyA;          // 甲方 (常为本单位, 可默认填充)
  final String partyB;          // 乙方
  final String contractType;    // 借款 / 采购 / 服务 / 保密 / 其它
  final String purpose;         // 合同标的 / 用印目的
  final DateTime? startDate;
  final DateTime? endDate;
  final double? amount;
  final String applicant;       // 申请人
  final String? businessOwner;  // 业务负责人
  final SealStatus status;
  final DateTime submittedAt;
  final List<ApprovalStep> approvals;
  final List<String> attachments; // 附件文件名 (真实版应是 File 或 URL)
  final List<BorrowRecord> borrowRecords; // 借阅记录

  const SealApplication({
    required this.id,
    required this.partyA,
    required this.partyB,
    required this.contractType,
    required this.purpose,
    required this.startDate,
    required this.endDate,
    this.amount,
    required this.applicant,
    this.businessOwner,
    required this.status,
    required this.submittedAt,
    this.approvals = const [],
    this.attachments = const [],
    this.borrowRecords = const [],
  });

  SealApplication copyWith({
    SealStatus? status,
    List<ApprovalStep>? approvals,
    List<BorrowRecord>? borrowRecords,
  }) => SealApplication(
    id: id,
    partyA: partyA,
    partyB: partyB,
    contractType: contractType,
    purpose: purpose,
    startDate: startDate,
    endDate: endDate,
    amount: amount,
    applicant: applicant,
    businessOwner: businessOwner,
    status: status ?? this.status,
    submittedAt: submittedAt,
    approvals: approvals ?? this.approvals,
    attachments: attachments,
    borrowRecords: borrowRecords ?? this.borrowRecords,
  );

  /// 是否允许借阅 (审批通过 / 已用印 / 已归档 都可以)
  bool get canBorrow =>
      status == SealStatus.approved ||
      status == SealStatus.sealed ||
      status == SealStatus.archived;
}

// ═══════════════════════════════════════════════════════════════════════════
// 语义 / 显示帮助函数
// ═══════════════════════════════════════════════════════════════════════════

extension _SealStatusX on SealStatus {
  String get label => const {
        SealStatus.draft: '起草中',
        SealStatus.approving: '审批中',
        SealStatus.approved: '待用印',
        SealStatus.sealed: '待归档',
        SealStatus.archived: '已归档',
        SealStatus.rejected: '已驳回',
      }[this]!;

  String get en => const {
        SealStatus.draft: 'DRAFT',
        SealStatus.approving: 'IN REVIEW',
        SealStatus.approved: 'AWAITING SEAL',
        SealStatus.sealed: 'AWAITING ARCHIVE',
        SealStatus.archived: 'ARCHIVED',
        SealStatus.rejected: 'REJECTED',
      }[this]!;

  Color get tint {
    switch (this) {
      case SealStatus.approving:
        return LhColors.copper;
      case SealStatus.approved:
      case SealStatus.sealed:
        return const Color(0xFF6B7A94); // 冷蓝灰, 进行中
      case SealStatus.archived:
        return const Color(0xFF5F7A5A); // 深绿, 完成
      case SealStatus.rejected:
        return LhColors.neg;
      case SealStatus.draft:
        return LhColors.mute;
    }
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtAmount(double v) {
  if (v.abs() >= 1e8) return '${(v / 1e8).toStringAsFixed(2)} 亿';
  if (v.abs() >= 1e4) return '${(v / 1e4).toStringAsFixed(1)} 万';
  return v.toStringAsFixed(0);
}

// ═══════════════════════════════════════════════════════════════════════════
// 页面 chrome —— editorial 返回键 + 页面背景 + 卡片装饰
// ═══════════════════════════════════════════════════════════════════════════

/// v3.7: 编辑室返回键 (mono ‹ + sans '返回')
Widget buildBackButton({required VoidCallback onTap, String label = '返回'}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '‹',
            style: LhTypography.mono(
              size: 15,
              color: LhColors.mute,
              weight: FontWeight.w600,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: LhTypography.sans(
              size: 10.5,
              color: LhColors.mute,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// v3.7 warm cream 3-stop 卡装饰 (near-white 纸感)
BoxDecoration paperCardDecoration({bool isExpanded = false}) => BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFC),
          Color(0xFFFAF8F0),
          Color(0xFFF2EFDF),
        ],
        stops: [0.0, 0.6, 1.0],
      ),
      border: Border.all(
        color: isExpanded
            ? LhColors.ink2.withAlpha(50)
            : const Color(0xFFDDD5C0),
        width: 1,
      ),
      borderRadius: BorderRadius.circular(7),
      boxShadow: [
        BoxShadow(
          color: isExpanded
              ? const Color(0x140A0A0F)
              : const Color(0x0C0A0A0F),
          blurRadius: isExpanded ? 6 : 3,
          offset: Offset(0, isExpanded ? 2 : 1),
        ),
      ],
    );

/// hero panel 装饰 (warm cream 3-stop, 供 masthead)
BoxDecoration heroPanelDecoration() => BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFDF7),
          Color(0xFFF8F0DA),
          Color(0xFFEFE4C6),
        ],
        stops: [0.0, 0.6, 1.0],
      ),
      border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0A0A0F),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    );

/// 状态胶囊 (无 fill, hairline 边框 + 语义色文字)
Widget buildStatusChip(SealStatus s) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: s.tint.withAlpha(12),
      border: Border.all(color: s.tint.withAlpha(70), width: 0.8),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      s.label,
      style: LhTypography.sans(
        size: 8.5,
        color: s.tint,
        weight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Demo 数据 (用印 / 借阅页共用; 生产环境走 service/API)
// ═══════════════════════════════════════════════════════════════════════════

List<SealApplication> contractSealingDemoApps() {
  return [
    SealApplication(
      id: 'YY-20260701-003',
      partyA: '星和电力集团有限公司',
      partyB: '平安银行股份有限公司',
      contractType: '借款',
      purpose: '2026 Q3 流动资金授信',
      startDate: DateTime(2026, 7, 5),
      endDate: DateTime(2027, 7, 4),
      amount: 5.0e7,
      applicant: '张伟',
      businessOwner: '李峰',
      status: SealStatus.approving,
      submittedAt: DateTime(2026, 7, 1, 10, 24),
      approvals: [
        ApprovalStep(
          role: '部门经理',
          approver: '王强',
          at: DateTime(2026, 7, 1, 14, 12),
          action: ApprovalAction.approved,
          comment: '同意, 请后续按合规流转',
        ),
        const ApprovalStep(role: '分管副总', approver: '陈丽'),
        const ApprovalStep(role: '法务复核', approver: '刘敏'),
      ],
      attachments: ['借款合同_v3_final.pdf'],
    ),
    SealApplication(
      id: 'YY-20260628-011',
      partyA: '星和电力集团有限公司',
      partyB: '中国石油化工股份有限公司',
      contractType: '采购',
      purpose: '92# 汽油季度采购框架',
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 9, 30),
      amount: 1.2e8,
      applicant: '张伟',
      businessOwner: '赵斌',
      status: SealStatus.sealed,
      submittedAt: DateTime(2026, 6, 28, 9, 30),
      approvals: [
        ApprovalStep(
          role: '部门经理',
          approver: '王强',
          at: DateTime(2026, 6, 28, 11, 0),
          action: ApprovalAction.approved,
          comment: '同意',
        ),
        ApprovalStep(
          role: '分管副总',
          approver: '陈丽',
          at: DateTime(2026, 6, 29, 15, 20),
          action: ApprovalAction.approved,
        ),
        ApprovalStep(
          role: '法务复核',
          approver: '刘敏',
          at: DateTime(2026, 6, 30, 10, 5),
          action: ApprovalAction.approved,
        ),
      ],
      attachments: ['采购框架合同.pdf'],
      borrowRecords: [
        BorrowRecord(
          id: 'JY-20260702-001',
          borrowerUnit: '中石化华东分公司',
          purpose: '季度对账备查',
          medium: '电子件',
          borrowedAt: DateTime(2026, 7, 2, 9, 15),
          expiresAt: DateTime(2026, 8, 1),
          applicant: '张伟',
          downloadCount: 1,
        ),
      ],
    ),
    SealApplication(
      id: 'YY-20260625-007',
      partyA: '星和电力集团有限公司',
      partyB: '深圳市卓越信息服务有限公司',
      contractType: '服务',
      purpose: 'NOVA 平台 SaaS 年度订阅',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2027, 5, 31),
      amount: 3.5e5,
      applicant: '张伟',
      businessOwner: '穆穆',
      status: SealStatus.archived,
      submittedAt: DateTime(2026, 6, 25, 16, 10),
      approvals: [
        ApprovalStep(
          role: '部门经理',
          approver: '王强',
          at: DateTime(2026, 6, 25, 17, 30),
          action: ApprovalAction.approved,
        ),
        ApprovalStep(
          role: '法务复核',
          approver: '刘敏',
          at: DateTime(2026, 6, 26, 9, 0),
          action: ApprovalAction.approved,
        ),
      ],
      attachments: ['NOVA_SaaS_订阅协议.pdf'],
    ),
  ];
}

int contractSealingActiveBorrowCount() {
  return contractSealingDemoApps()
      .expand((a) => a.borrowRecords)
      .where((r) => !r.isExpired)
      .length;
}

// ═══════════════════════════════════════════════════════════════════════════
// 主页: 合同用印列表
// ═══════════════════════════════════════════════════════════════════════════

class ContractSealingPage extends StatefulWidget {
  const ContractSealingPage({super.key});
  @override
  State<ContractSealingPage> createState() => _ContractSealingPageState();
}

class _ContractSealingPageState extends State<ContractSealingPage> {
  final List<SealApplication> _apps = contractSealingDemoApps();

  // segmented: 我的申请 · 待我审批 · 全部
  int _seg = 0;
  // status filter chip: null = 全部
  SealStatus? _statusFilter;

  static const _segTabs = ['我的申请', '待我审批', '全部'];

  List<SealApplication> get _filtered {
    var list = List<SealApplication>.from(_apps);
    // segmented 过滤 (demo: 简化)
    if (_seg == 0) {
      list = list.where((a) => a.applicant == '张伟').toList();
    } else if (_seg == 1) {
      list = list
          .where((a) =>
              a.status == SealStatus.approving &&
              a.approvals.any((s) => s.action == ApprovalAction.pending))
          .toList();
    }
    if (_statusFilter != null) {
      list = list.where((a) => a.status == _statusFilter).toList();
    }
    list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LhColors.paper,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFDF7),
              Color(0xFFFCF8EC),
              Color(0xFFF5EEDA),
              Color(0xFFEBE2CC),
            ],
            stops: [0.0, 0.32, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSegmentedTabs(),
              _buildStatusFilterRow(),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildCreateFab(),
    );
  }

  // ── Header (editorial masthead) ────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          buildBackButton(onTap: () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: const Color(0xFFDDD5C0)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '合同用印 · CONTRACT SEALING',
                  style: LhTypography.mono(
                    size: 8.5,
                    color: LhColors.mute,
                    weight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_apps.length} 项  ·  ${_apps.where((a) => a.status == SealStatus.approving).length} 审批中',
                  style: LhTypography.sans(
                    size: 10.5,
                    color: LhColors.mute2,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 检索入口 —— 编辑室 icon, 无 chrome
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _SearchPage(allApps: _apps),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.search_rounded,
                size: 18,
                color: LhColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented tabs ─────────────────────────────────────────────
  Widget _buildSegmentedTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFDDD5C0), width: 1),
          bottom: BorderSide(color: Color(0xFFDDD5C0), width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: List.generate(_segTabs.length, (i) {
            final isOn = _seg == i;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _seg = i),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Center(
                        child: Text(
                          _segTabs[i],
                          style: LhTypography.sans(
                            size: 12,
                            color: isOn ? LhColors.ink : LhColors.mute,
                            weight: isOn ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    if (isOn)
                      Positioned(
                        bottom: -1,
                        left: 0,
                        right: 0,
                        child: Container(height: 2, color: LhColors.copper),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Status filter chips (horizontal scroll) ────────────────────
  Widget _buildStatusFilterRow() {
    final items = <SealStatus?>[
      null,
      SealStatus.approving,
      SealStatus.approved,
      SealStatus.sealed,
      SealStatus.archived,
      SealStatus.rejected,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: SizedBox(
        height: 26,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final s = items[i];
            final label = s?.label ?? '全部';
            final isOn = _statusFilter == s;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _statusFilter = s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        label,
                        style: LhTypography.sans(
                          size: 10.5,
                          color: isOn ? LhColors.copper : LhColors.mute,
                          weight: isOn ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (isOn)
                      Positioned(
                        bottom: 0,
                        left: 4,
                        right: 4,
                        child: Container(height: 1.5, color: LhColors.copper),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── List ───────────────────────────────────────────────────────
  Widget _buildList() {
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Text(
            '暂无匹配的用印申请',
            style: LhTypography.sans(size: 12, color: LhColors.mute2),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
      itemCount: list.length,
      itemBuilder: (ctx, i) => _buildAppCard(i, list[i]),
    );
  }

  Widget _buildAppCard(int i, SealApplication a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () async {
            final updated = await Navigator.of(context).push<SealApplication>(
              MaterialPageRoute(
                builder: (_) => _SealApplicationDetailPage(app: a),
              ),
            );
            if (updated != null) {
              setState(() {
                final idx = _apps.indexWhere((x) => x.id == a.id);
                if (idx >= 0) _apps[idx] = updated;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
            decoration: paperCardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank
                SizedBox(
                  width: 30,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: LhTypography.mono(
                      size: 11.5,
                      color: i < 3 ? LhColors.copper : LhColors.mute2,
                      weight: i < 3 ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                // Left: 编号 + 乙方 + 目的
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 编号
                      Text(
                        a.id,
                        style: LhTypography.mono(
                          size: 8.5,
                          color: LhColors.mute2,
                          weight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 乙方
                      Text(
                        a.partyB,
                        style: LhTypography.sans(
                          size: 12.5,
                          color: LhColors.ink,
                          weight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // 目的
                      Text(
                        '${a.contractType} · ${a.purpose}',
                        style: LhTypography.sans(
                          size: 9.5,
                          color: LhColors.mute,
                          weight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      buildStatusChip(a.status),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Right: 金额 + 日期
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '金额 AMOUNT',
                      style: LhTypography.mono(
                        size: 7.5,
                        color: LhColors.mute,
                        weight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: a.amount == null
                                ? '—'
                                : _fmtAmount(a.amount!),
                            style: LhTypography.number(
                              size: 16,
                              color: LhColors.ink,
                            ),
                          ),
                          if (a.amount != null)
                            TextSpan(
                              text: ' 元',
                              style: LhTypography.sans(
                                size: 9,
                                color: LhColors.mute,
                                weight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      a.startDate == null || a.endDate == null
                          ? '⚠ 日期未填'
                          : '${_fmtDate(a.startDate!)} ›',
                      style: LhTypography.mono(
                        size: 8.5,
                        color: a.startDate == null
                            ? LhColors.neg
                            : LhColors.mute2,
                        weight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Create FAB ─────────────────────────────────────────────────
  Widget _buildCreateFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 6),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final newApp = await Navigator.of(context).push<SealApplication>(
            MaterialPageRoute(builder: (_) => const _CreateSealApplicationPage()),
          );
          if (newApp != null) setState(() => _apps.insert(0, newApp));
        },
        backgroundColor: LhColors.copper,
        elevation: 4,
        icon: const Icon(Icons.add, size: 18, color: Colors.white),
        label: Text(
          '新建用印申请',
          style: LhTypography.sans(
            size: 11.5,
            color: Colors.white,
            weight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 详情页
// ═══════════════════════════════════════════════════════════════════════════

class _SealApplicationDetailPage extends StatefulWidget {
  final SealApplication app;
  const _SealApplicationDetailPage({required this.app});
  @override
  State<_SealApplicationDetailPage> createState() =>
      _SealApplicationDetailPageState();
}

class _SealApplicationDetailPageState
    extends State<_SealApplicationDetailPage> {
  late SealApplication _app = widget.app;

  @override
  Widget build(BuildContext context) {
    final a = _app;
    return Scaffold(
      backgroundColor: LhColors.paper,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFDF7), Color(0xFFEBE2CC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMasthead(a),
                      const SizedBox(height: 16),
                      _buildKicker('合同信息 · CONTRACT'),
                      const SizedBox(height: 8),
                      _buildFieldsCard(a),
                      const SizedBox(height: 16),
                      _buildKicker('审批链路 · APPROVAL FLOW'),
                      const SizedBox(height: 8),
                      _buildTimelineCard(a),
                      const SizedBox(height: 16),
                      _buildKicker('附件 · ATTACHMENTS'),
                      const SizedBox(height: 8),
                      _buildAttachmentsCard(a),
                      const SizedBox(height: 16),
                      // ── 借阅区: 已借阅记录 + 发起借阅入口 ──
                      _buildBorrowSection(a),
                    ],
                  ),
                ),
              ),
              if (a.status == SealStatus.approving) _buildActionBar(a),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: Row(
          children: [
            buildBackButton(onTap: () => Navigator.of(context).pop(_app)),
            const Spacer(),
            Text(
              '用印详情 · L2',
              style: LhTypography.mono(
                size: 8.5,
                color: LhColors.mute2,
                weight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      );

  Widget _buildMasthead(SealApplication a) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: heroPanelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  a.id,
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.mute,
                    weight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                buildStatusChip(a.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              a.purpose,
              style: LhTypography.sans(
                size: 18,
                color: LhColors.ink,
                weight: FontWeight.w700,
                height: 1.2,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              a.contractType,
              style: LhTypography.mono(
                size: 9,
                color: LhColors.copper,
                weight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _miniStat('金额', _fmtAmount(a.amount ?? 0), '元')),
                Container(
                  height: 26,
                  width: 1,
                  color: const Color(0xFFDDD5C0),
                ),
                Expanded(
                  child: _miniStat(
                    '期限',
                    a.startDate != null && a.endDate != null
                        ? '${a.endDate!.year - a.startDate!.year}'
                        : '—',
                    a.startDate != null && a.endDate != null ? '年' : '',
                  ),
                ),
                Container(
                  height: 26,
                  width: 1,
                  color: const Color(0xFFDDD5C0),
                ),
                Expanded(
                  child: _miniStat(
                    '审批',
                    '${a.approvals.where((s) => s.action == ApprovalAction.approved).length}',
                    ' / ${a.approvals.length}',
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _miniStat(String label, String num, String unit) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: LhTypography.mono(
                size: 7.5,
                color: LhColors.mute,
                weight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: num,
                    style: LhTypography.number(size: 14, color: LhColors.ink),
                  ),
                  TextSpan(
                    text: unit,
                    style: LhTypography.sans(
                      size: 9,
                      color: LhColors.mute,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildKicker(String label) => Text(
        label,
        style: LhTypography.mono(
          size: 8.5,
          color: LhColors.mute,
          weight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );

  Widget _buildFieldsCard(SealApplication a) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: paperCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldRow('甲方', a.partyA),
            _fieldRow('乙方', a.partyB),
            _fieldRow(
              '起止日期',
              a.startDate != null && a.endDate != null
                  ? '${_fmtDate(a.startDate!)}  →  ${_fmtDate(a.endDate!)}'
                  : '⚠ 未填写 —— 请从合同正文中补齐',
              highlight: a.startDate == null,
            ),
            _fieldRow('申请人', a.applicant),
            _fieldRow('业务负责人', a.businessOwner ?? '—'),
            _fieldRow(
              '提交时间',
              '${_fmtDate(a.submittedAt)} ${a.submittedAt.hour.toString().padLeft(2, '0')}:${a.submittedAt.minute.toString().padLeft(2, '0')}',
              last: true,
            ),
          ],
        ),
      );

  Widget _fieldRow(String label, String value,
      {bool highlight = false, bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: LhTypography.sans(
                size: 10,
                color: LhColors.mute,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: LhTypography.sans(
                size: 11.5,
                color: highlight ? LhColors.neg : LhColors.ink,
                weight: highlight ? FontWeight.w700 : FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 时间线卡: 竖向, 每一步是一个 dot + 内容
  Widget _buildTimelineCard(SealApplication a) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: paperCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(a.approvals.length, (i) {
          final step = a.approvals[i];
          final isLast = i == a.approvals.length - 1;
          final done = step.action == ApprovalAction.approved;
          final rejected = step.action == ApprovalAction.rejected;
          final Color dotColor = rejected
              ? LhColors.neg
              : done
                  ? LhColors.copper
                  : LhColors.mute2;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dot + connector
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: done ? dotColor : Colors.transparent,
                          border: Border.all(color: dotColor, width: 1.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 1,
                            color: const Color(0xFFDDD5C0),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              step.role,
                              style: LhTypography.sans(
                                size: 11.5,
                                color: LhColors.ink,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              step.approver,
                              style: LhTypography.sans(
                                size: 10.5,
                                color: LhColors.mute,
                                weight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            if (step.at != null)
                              Text(
                                _fmtDate(step.at!),
                                style: LhTypography.mono(
                                  size: 8.5,
                                  color: LhColors.mute2,
                                  weight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _approvalActionText(step.action),
                          style: LhTypography.mono(
                            size: 9,
                            color: rejected
                                ? LhColors.neg
                                : done
                                    ? LhColors.copper
                                    : LhColors.mute2,
                            weight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (step.comment != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            '「${step.comment}」',
                            style: LhTypography.sans(
                              size: 10.5,
                              color: LhColors.mute,
                              weight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  String _approvalActionText(ApprovalAction a) {
    switch (a) {
      case ApprovalAction.pending:
        return '待处理 · PENDING';
      case ApprovalAction.approved:
        return '已通过 · APPROVED';
      case ApprovalAction.rejected:
        return '已驳回 · REJECTED';
      case ApprovalAction.transferred:
        return '已转办 · TRANSFERRED';
    }
  }

  Widget _buildAttachmentsCard(SealApplication a) {
    if (a.attachments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: paperCardDecoration(),
        child: Text(
          '无附件',
          style: LhTypography.sans(
            size: 11,
            color: LhColors.mute2,
            weight: FontWeight.w500,
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: paperCardDecoration(),
      child: Column(
        children: a.attachments
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 15, color: LhColors.mute),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: LhTypography.sans(
                            size: 11,
                            color: LhColors.ink2,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '预览 ›',
                        style: LhTypography.mono(
                          size: 9,
                          color: LhColors.copper,
                          weight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  // 底部审批操作栏 (仅审批中显示)
  Widget _buildActionBar(SealApplication a) {
    // 简化: 找第一个 pending 的
    final nextStep = a.approvals
        .firstWhere((s) => s.action == ApprovalAction.pending, orElse: () => a.approvals.last);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFEFCF5),
        border: Border(top: BorderSide(color: Color(0xFFDDD5C0), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '待你审批 · ${nextStep.role}',
              style: LhTypography.sans(
                size: 10.5,
                color: LhColors.mute,
                weight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _act(ApprovalAction.rejected, nextStep),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                '驳回',
                style: LhTypography.sans(
                  size: 12,
                  color: LhColors.neg,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _act(ApprovalAction.approved, nextStep),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: LhColors.copper,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '通过',
                style: LhTypography.sans(
                  size: 12,
                  color: Colors.white,
                  weight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _act(ApprovalAction action, ApprovalStep step) {
    final idx = _app.approvals.indexOf(step);
    if (idx < 0) return;
    final newApprovals = List<ApprovalStep>.from(_app.approvals);
    newApprovals[idx] = ApprovalStep(
      role: step.role,
      approver: step.approver,
      at: DateTime.now(),
      action: action,
      comment: step.comment,
    );
    SealStatus newStatus = _app.status;
    if (action == ApprovalAction.rejected) {
      newStatus = SealStatus.rejected;
    } else if (newApprovals
        .every((s) => s.action == ApprovalAction.approved)) {
      newStatus = SealStatus.approved;
    }
    setState(() {
      _app = _app.copyWith(status: newStatus, approvals: newApprovals);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 借阅 section
  //   - 已有借阅记录列表 (每条: 借阅单位/用途/有效期/下载次数)
  //   - 底部"发起借阅"按钮 (仅 canBorrow 状态可用)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildBorrowSection(SealApplication a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildKicker('借阅记录 · BORROW LOG')),
            if (a.canBorrow)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final rec = await Navigator.of(context).push<BorrowRecord>(
                    MaterialPageRoute(
                      builder: (_) => _BorrowPage(app: a),
                    ),
                  );
                  if (rec != null) {
                    setState(() {
                      _app = _app.copyWith(
                        borrowRecords: [rec, ..._app.borrowRecords],
                      );
                    });
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 12, color: LhColors.copper),
                    const SizedBox(width: 2),
                    Text(
                      '发起借阅',
                      style: LhTypography.sans(
                        size: 10,
                        color: LhColors.copper,
                        weight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (a.borrowRecords.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: paperCardDecoration(),
            child: Text(
              a.canBorrow
                  ? '暂无借阅记录  ·  tap 发起借阅生成带水印的电子件'
                  : '合同尚未通过审批,暂不可借阅',
              style: LhTypography.sans(
                size: 10.5,
                color: LhColors.mute2,
                weight: FontWeight.w500,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: paperCardDecoration(),
            child: Column(
              children: List.generate(a.borrowRecords.length, (i) {
                final r = a.borrowRecords[i];
                final isLast = i == a.borrowRecords.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            r.id,
                            style: LhTypography.mono(
                              size: 8.5,
                              color: LhColors.mute2,
                              weight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: r.isExpired
                                  ? LhColors.mute2.withAlpha(20)
                                  : LhColors.copper.withAlpha(15),
                              border: Border.all(
                                color: r.isExpired
                                    ? LhColors.mute2
                                    : LhColors.copper.withAlpha(120),
                                width: 0.6,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              r.isExpired ? '已失效' : '有效中',
                              style: LhTypography.sans(
                                size: 7.5,
                                color: r.isExpired
                                    ? LhColors.mute
                                    : LhColors.copper,
                                weight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            r.medium,
                            style: LhTypography.mono(
                              size: 8.5,
                              color: LhColors.mute,
                              weight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        r.borrowerUnit,
                        style: LhTypography.sans(
                          size: 12,
                          color: LhColors.ink,
                          weight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.purpose,
                        style: LhTypography.sans(
                          size: 10,
                          color: LhColors.mute,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_fmtDate(r.borrowedAt)} → ${_fmtDate(r.expiresAt)}  ·  下载 ${r.downloadCount} 次',
                        style: LhTypography.mono(
                          size: 8.5,
                          color: LhColors.mute2,
                          weight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 新建申请表单
// ═══════════════════════════════════════════════════════════════════════════

class _CreateSealApplicationPage extends StatefulWidget {
  const _CreateSealApplicationPage();
  @override
  State<_CreateSealApplicationPage> createState() =>
      _CreateSealApplicationPageState();
}

class _CreateSealApplicationPageState
    extends State<_CreateSealApplicationPage> {
  final _partyBCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  String _contractType = '采购';
  DateTime? _start;
  DateTime? _end;
  bool _validated = false;

  static const _contractTypes = ['借款', '采购', '服务', '保密', '其它'];

  @override
  void dispose() {
    _partyBCtrl.dispose();
    _purposeCtrl.dispose();
    _amountCtrl.dispose();
    _ownerCtrl.dispose();
    super.dispose();
  }

  String get _autoId {
    final now = DateTime.now();
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'YY-$ymd-XXX'; // 服务端最终生成序号
  }

  bool get _canSubmit =>
      _partyBCtrl.text.trim().isNotEmpty &&
      _purposeCtrl.text.trim().isNotEmpty &&
      _start != null &&
      _end != null &&
      _end!.isAfter(_start!);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LhColors.paper,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFDF7), Color(0xFFEBE2CC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                child: Row(
                  children: [
                    buildBackButton(onTap: () => Navigator.of(context).pop()),
                    const Spacer(),
                    Text(
                      '新建申请',
                      style: LhTypography.mono(
                        size: 8.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Auto-generated id preview
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: heroPanelDecoration(),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '编号 · AUTO ID',
                                  style: LhTypography.mono(
                                    size: 8.5,
                                    color: LhColors.mute,
                                    weight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _autoId,
                                  style: LhTypography.mono(
                                    size: 16,
                                    color: LhColors.ink,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              '系统自动生成\n无需手工编号',
                              textAlign: TextAlign.right,
                              style: LhTypography.sans(
                                size: 9.5,
                                color: LhColors.copper,
                                weight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionKicker('合同信息 · CONTRACT'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: paperCardDecoration(),
                        child: Column(
                          children: [
                            _inputField('乙方 *', _partyBCtrl, '合同对方名称'),
                            const SizedBox(height: 12),
                            _dropdownField(
                              '合同类型 *',
                              _contractType,
                              _contractTypes,
                              (v) => setState(() => _contractType = v),
                            ),
                            const SizedBox(height: 12),
                            _inputField('合同标的 / 用印目的 *', _purposeCtrl,
                                '简要说明合同内容'),
                            const SizedBox(height: 12),
                            _inputField('合同金额', _amountCtrl, '元 (可选)',
                                keyboard: TextInputType.number),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionKicker('起止日期 · TERM'),
                      const SizedBox(height: 4),
                      Text(
                        '⚠  日期必填。避免归档时反复翻查合同正文推算',
                        style: LhTypography.sans(
                          size: 9.5,
                          color: LhColors.neg,
                          weight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: paperCardDecoration(),
                        child: Row(
                          children: [
                            Expanded(
                              child: _dateField('起始日 *', _start, (d) {
                                setState(() => _start = d);
                              }),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '→',
                                style: LhTypography.mono(
                                  size: 15,
                                  color: LhColors.mute2,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _dateField('终止日 *', _end, (d) {
                                setState(() => _end = d);
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionKicker('业务负责人 · OWNER'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: paperCardDecoration(),
                        child: _inputField('姓名', _ownerCtrl, '业务侧对接人'),
                      ),
                      const SizedBox(height: 20),
                      _sectionKicker('附件 · ATTACHMENTS'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFFFFC), Color(0xFFF2EFDF)],
                          ),
                          border: Border.all(
                              color: const Color(0xFFDDD5C0), width: 1,
                              style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.upload_file_outlined,
                                size: 22, color: LhColors.mute),
                            const SizedBox(height: 6),
                            Text(
                              '点击上传合同扫描件',
                              style: LhTypography.sans(
                                size: 11,
                                color: LhColors.ink2,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '支持 PDF / JPG · 系统自动 OCR 抽取字段',
                              style: LhTypography.mono(
                                size: 8.5,
                                color: LhColors.mute2,
                                weight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Submit bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEFCF5),
                  border: Border(
                      top: BorderSide(color: Color(0xFFDDD5C0), width: 1)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Text(
                          '存草稿',
                          style: LhTypography.sans(
                            size: 12,
                            color: LhColors.mute,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!_canSubmit && _validated)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '请补齐 * 必填项',
                          style: LhTypography.sans(
                            size: 10,
                            color: LhColors.neg,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!_canSubmit) {
                          setState(() => _validated = true);
                          return;
                        }
                        Navigator.of(context).pop(SealApplication(
                          id: _autoId,
                          partyA: '星和电力集团有限公司',
                          partyB: _partyBCtrl.text.trim(),
                          contractType: _contractType,
                          purpose: _purposeCtrl.text.trim(),
                          startDate: _start,
                          endDate: _end,
                          amount: double.tryParse(_amountCtrl.text.trim()),
                          applicant: '张伟',
                          businessOwner: _ownerCtrl.text.trim().isEmpty
                              ? null
                              : _ownerCtrl.text.trim(),
                          status: SealStatus.approving,
                          submittedAt: DateTime.now(),
                          approvals: const [
                            ApprovalStep(role: '部门经理', approver: '王强'),
                            ApprovalStep(role: '分管副总', approver: '陈丽'),
                            ApprovalStep(role: '法务复核', approver: '刘敏'),
                          ],
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: _canSubmit
                              ? LhColors.copper
                              : LhColors.mute2,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '提交审批',
                          style: LhTypography.sans(
                            size: 12,
                            color: Colors.white,
                            weight: FontWeight.w700,
                            letterSpacing: 0.5,
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
      ),
    );
  }

  Widget _sectionKicker(String label) => Text(
        label,
        style: LhTypography.mono(
          size: 8.5,
          color: LhColors.mute,
          weight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );

  Widget _inputField(String label, TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text}) {
    final missing = _validated && ctrl.text.trim().isEmpty && label.endsWith('*');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.sans(
            size: 10,
            color: missing ? LhColors.neg : LhColors.mute,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          style: LhTypography.sans(
            size: 12,
            color: LhColors.ink,
            weight: FontWeight.w600,
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: LhTypography.sans(
              size: 11,
              color: LhColors.mute2,
              weight: FontWeight.w500,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 5),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: missing ? LhColors.neg : const Color(0xFFDDD5C0),
                  width: 1),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: missing ? LhColors.neg : const Color(0xFFDDD5C0),
                  width: 1),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: LhColors.copper, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(
      String label, String value, List<String> options, void Function(String) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.sans(
            size: 10,
            color: LhColors.mute,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFEFCF5),
            border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
            borderRadius: BorderRadius.circular(5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down,
                  color: LhColors.mute, size: 18),
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(
                          o,
                          style: LhTypography.sans(
                            size: 12,
                            color: LhColors.ink,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onPick(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateField(
      String label, DateTime? value, void Function(DateTime) onPick) {
    final missing = _validated && value == null && label.endsWith('*');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.sans(
            size: 10,
            color: missing ? LhColors.neg : LhColors.mute,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) onPick(picked);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEFCF5),
              border: Border.all(
                  color: missing ? LhColors.neg : const Color(0xFFDDD5C0),
                  width: 1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null ? '请选择' : _fmtDate(value),
                    style: LhTypography.mono(
                      size: 11,
                      color: value == null ? LhColors.mute2 : LhColors.ink,
                      weight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Icon(Icons.calendar_month_outlined,
                    size: 14, color: LhColors.mute),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 借阅主页: 我的借阅记录 + 可借阅合同
// ═══════════════════════════════════════════════════════════════════════════

class ContractBorrowPage extends StatefulWidget {
  const ContractBorrowPage({super.key});

  @override
  State<ContractBorrowPage> createState() => _ContractBorrowPageState();
}

class _ContractBorrowPageState extends State<ContractBorrowPage> {
  late List<SealApplication> _apps = contractSealingDemoApps();

  List<SealApplication> get _borrowable =>
      _apps.where((a) => a.canBorrow).toList();

  List<({BorrowRecord record, SealApplication app})> get _allRecords {
    final out = <({BorrowRecord record, SealApplication app})>[];
    for (final a in _apps) {
      for (final r in a.borrowRecords) {
        out.add((record: r, app: a));
      }
    }
    out.sort((a, b) => b.record.borrowedAt.compareTo(a.record.borrowedAt));
    return out;
  }

  Future<void> _openBorrow(SealApplication app) async {
    final idx = _apps.indexWhere((x) => x.id == app.id);
    if (idx < 0) return;
    final rec = await Navigator.of(context).push<BorrowRecord>(
      MaterialPageRoute(builder: (_) => _BorrowPage(app: _apps[idx])),
    );
    if (rec == null || !mounted) return;
    setState(() {
      final current = _apps[idx];
      _apps[idx] = current.copyWith(
        borrowRecords: [rec, ...current.borrowRecords],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = _allRecords;
    final borrowable = _borrowable;
    return Scaffold(
      backgroundColor: LhColors.paper,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFDF7), Color(0xFFFCF8EC), Color(0xFFF5EEDA)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
                child: Row(
                  children: [
                    buildBackButton(onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 14,
                      color: const Color(0xFFDDD5C0),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '合同借阅 · CONTRACT BORROW',
                            style: LhTypography.mono(
                              size: 8.5,
                              color: LhColors.mute,
                              weight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${records.length} 条记录  ·  ${records.where((e) => !e.record.isExpired).length} 有效中',
                            style: LhTypography.sans(
                              size: 10.5,
                              color: LhColors.mute2,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  children: [
                    Text(
                      '我的借阅 · MY BORROWS',
                      style: LhTypography.mono(
                        size: 8,
                        color: LhColors.mute2,
                        weight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (records.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: paperCardDecoration(),
                        child: Text(
                          '暂无借阅记录  ·  下方选择合同发起带水印电子件',
                          style: LhTypography.sans(
                            size: 10.5,
                            color: LhColors.mute2,
                            weight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        decoration: paperCardDecoration(),
                        child: Column(
                          children: List.generate(records.length, (i) {
                            final item = records[i];
                            final r = item.record;
                            final a = item.app;
                            final isLast = i == records.length - 1;
                            return Padding(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        r.id,
                                        style: LhTypography.mono(
                                          size: 8.5,
                                          color: LhColors.mute2,
                                          weight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: r.isExpired
                                              ? LhColors.mute2.withAlpha(20)
                                              : LhColors.copper.withAlpha(15),
                                          border: Border.all(
                                            color: r.isExpired
                                                ? LhColors.mute2
                                                : LhColors.copper
                                                    .withAlpha(120),
                                            width: 0.6,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                        child: Text(
                                          r.isExpired ? '已失效' : '有效中',
                                          style: LhTypography.sans(
                                            size: 7.5,
                                            color: r.isExpired
                                                ? LhColors.mute
                                                : LhColors.copper,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        r.medium,
                                        style: LhTypography.sans(
                                          size: 8.5,
                                          color: LhColors.mute2,
                                          weight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    r.borrowerUnit,
                                    style: LhTypography.sans(
                                      size: 12,
                                      color: LhColors.ink,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r.purpose,
                                    style: LhTypography.sans(
                                      size: 9.5,
                                      color: LhColors.mute,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${a.id}  ·  ${a.partyB}',
                                    style: LhTypography.mono(
                                      size: 8,
                                      color: LhColors.mute2,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '下载 ${r.downloadCount} 次',
                                    style: LhTypography.mono(
                                      size: 8.5,
                                      color: LhColors.mute2,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      '发起借阅 · NEW BORROW',
                      style: LhTypography.mono(
                        size: 8,
                        color: LhColors.mute2,
                        weight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...borrowable.map((a) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => _openBorrow(a),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                12,
                                12,
                              ),
                              decoration: paperCardDecoration(),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          a.id,
                                          style: LhTypography.mono(
                                            size: 9,
                                            color: LhColors.mute2,
                                            weight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          a.partyB,
                                          style: LhTypography.sans(
                                            size: 12.5,
                                            color: LhColors.ink,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          a.purpose,
                                          style: LhTypography.sans(
                                            size: 9.5,
                                            color: LhColors.mute,
                                            weight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  buildStatusChip(a.status),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.add,
                                    size: 16,
                                    color: LhColors.copper,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 我的 tab 入口卡片 (供"我的"页面调用)
//   用法:
//     Column(
//       children: [
//         ContractSealingEntryCard(),
//         ContractBorrowEntryCard(),
//         ...其他入口
//       ],
//     )
// ═══════════════════════════════════════════════════════════════════════════

Widget _buildLhEntryCard({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  String? trailingBadge,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: paperCardDecoration(),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: LhColors.copper.withAlpha(18),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: LhColors.copper),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: LhTypography.sans(
                        size: 13,
                        color: LhColors.ink,
                        weight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: LhTypography.sans(
                        size: 9.5,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingBadge != null) ...[
                Text(
                  trailingBadge,
                  style: LhTypography.mono(
                    size: 9.5,
                    color: LhColors.copper,
                    weight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right, size: 16, color: LhColors.mute2),
            ],
          ),
        ),
      ),
    ),
  );
}

class ContractSealingEntryCard extends StatelessWidget {
  final int pendingCount;
  const ContractSealingEntryCard({super.key, this.pendingCount = 2});

  @override
  Widget build(BuildContext context) {
    return _buildLhEntryCard(
      icon: Icons.assignment_outlined,
      title: '合同用印',
      subtitle: '检索 · 用印审批 · 追踪归档',
      trailingBadge: pendingCount > 0 ? '$pendingCount 待办' : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ContractSealingPage()),
      ),
    );
  }
}

class ContractBorrowEntryCard extends StatelessWidget {
  final int activeCount;
  const ContractBorrowEntryCard({super.key, this.activeCount = 1});

  @override
  Widget build(BuildContext context) {
    final count = activeCount > 0
        ? activeCount
        : contractSealingActiveBorrowCount();
    return _buildLhEntryCard(
      icon: Icons.menu_book_outlined,
      title: '合同借阅',
      subtitle: '水印电子件 · 有效期管控 · 审计追溯',
      trailingBadge: count > 0 ? '$count 有效' : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ContractBorrowPage()),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 检索页 —— 全文 + 结构化字段复合搜索
//
//   痛点解: 之前"只能按编号查台账", 现在:
//     · 查询框: 关键词 (乙方/编号/目的/合同类型 任意)
//     · Advanced filter: 合同类型 / 状态 / 日期范围 / 金额范围
//     · Recent searches 记忆 (最近 5 条)
//     · 空状态给检索提示
//     · Results 用主页同款卡片渲染
// ═══════════════════════════════════════════════════════════════════════════

class _SearchPage extends StatefulWidget {
  final List<SealApplication> allApps;
  const _SearchPage({required this.allApps});
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _typeFilter;    // 合同类型
  SealStatus? _statusFilter;
  bool _advancedOpen = false;

  // demo: static recent
  static final List<String> _recent = ['平安银行', '92#', '中石化'];

  static const _contractTypes = ['借款', '采购', '服务', '保密', '其它'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SealApplication> get _results {
    if (_query.trim().isEmpty && _typeFilter == null && _statusFilter == null) {
      return const [];
    }
    final q = _query.trim().toLowerCase();
    return widget.allApps.where((a) {
      // 关键词: 乙方/编号/目的/合同类型 任一匹配
      if (q.isNotEmpty) {
        final hay = '${a.partyB} ${a.id} ${a.purpose} ${a.contractType} ${a.partyA}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_typeFilter != null && a.contractType != _typeFilter) return false;
      if (_statusFilter != null && a.status != _statusFilter) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: LhColors.paper,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFDF7),
              Color(0xFFFCF8EC),
              Color(0xFFF5EEDA),
              Color(0xFFEBE2CC),
            ],
            stops: [0.0, 0.32, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: back + search input
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    buildBackButton(onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEFCF5),
                          border: Border.all(
                              color: const Color(0xFFDDD5C0), width: 1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                size: 15, color: LhColors.mute),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                autofocus: true,
                                style: LhTypography.sans(
                                  size: 12,
                                  color: LhColors.ink,
                                  weight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '搜索乙方 / 编号 / 目的 / 类型 / 关键词',
                                  hintStyle: LhTypography.sans(
                                    size: 11,
                                    color: LhColors.mute2,
                                    weight: FontWeight.w500,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onChanged: (v) => setState(() => _query = v),
                                onSubmitted: (v) {
                                  if (v.trim().isNotEmpty &&
                                      !_recent.contains(v.trim())) {
                                    _recent.insert(0, v.trim());
                                    if (_recent.length > 5) _recent.removeLast();
                                  }
                                },
                              ),
                            ),
                            if (_query.isNotEmpty)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                                child: Icon(Icons.close, size: 14,
                                    color: LhColors.mute2),
                              ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _advancedOpen = !_advancedOpen),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Icon(
                          Icons.tune,
                          size: 16,
                          color: (_typeFilter != null || _statusFilter != null)
                              ? LhColors.copper
                              : LhColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Advanced filter panel
              if (_advancedOpen) _buildAdvancedFilter(),
              // Hairline separator
              Container(height: 1, color: const Color(0xFFDDD5C0)),
              // Body
              Expanded(
                child: _query.trim().isEmpty &&
                        _typeFilter == null &&
                        _statusFilter == null
                    ? _buildEmptyState()
                    : _buildResults(results),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedFilter() {
    return Container(
      color: const Color(0xFFFDF9EC),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '合同类型 · TYPE',
            style: LhTypography.mono(
              size: 8.5,
              color: LhColors.mute,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [null, ..._contractTypes].map((t) {
              final on = _typeFilter == t;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _typeFilter = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: on
                        ? LhColors.copper.withAlpha(20)
                        : Colors.transparent,
                    border: Border.all(
                      color: on
                          ? LhColors.copper.withAlpha(140)
                          : const Color(0xFFDDD5C0),
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    t ?? '全部',
                    style: LhTypography.sans(
                      size: 10.5,
                      color: on ? LhColors.copper : LhColors.mute,
                      weight: on ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            '状态 · STATUS',
            style: LhTypography.mono(
              size: 8.5,
              color: LhColors.mute,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              null,
              SealStatus.approving,
              SealStatus.approved,
              SealStatus.sealed,
              SealStatus.archived,
              SealStatus.rejected,
            ].map((s) {
              final on = _statusFilter == s;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _statusFilter = s),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: on
                        ? LhColors.copper.withAlpha(20)
                        : Colors.transparent,
                    border: Border.all(
                      color: on
                          ? LhColors.copper.withAlpha(140)
                          : const Color(0xFFDDD5C0),
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    s?.label ?? '全部',
                    style: LhTypography.sans(
                      size: 10.5,
                      color: on ? LhColors.copper : LhColors.mute,
                      weight: on ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_recent.isNotEmpty) ...[
            Text(
              '最近查询 · RECENT',
              style: LhTypography.mono(
                size: 8.5,
                color: LhColors.mute,
                weight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _recent.map((q) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _searchCtrl.text = q;
                    setState(() => _query = q);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEFCF5),
                      border: Border.all(
                          color: const Color(0xFFDDD5C0), width: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 11, color: LhColors.mute2),
                        const SizedBox(width: 4),
                        Text(
                          q,
                          style: LhTypography.sans(
                            size: 10.5,
                            color: LhColors.ink2,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            '搜索提示 · TIPS',
            style: LhTypography.mono(
              size: 8.5,
              color: LhColors.mute,
              weight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          _tipLine('乙方名称  例  "平安银行"'),
          _tipLine('系统编号  例  "YY-20260701"'),
          _tipLine('合同标的关键词  例  "92# 汽油"'),
          _tipLine('合同类型  例  "借款" "采购"'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: paperCardDecoration(),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: LhColors.copper),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'v2 将支持合同正文全文搜索 (OCR 抽取)',
                    style: LhTypography.sans(
                      size: 10.5,
                      color: LhColors.ink2,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('· ',
                style: LhTypography.mono(
                    size: 10, color: LhColors.mute2, weight: FontWeight.w700)),
            Expanded(
              child: Text(
                text,
                style: LhTypography.sans(
                  size: 10.5,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildResults(List<SealApplication> results) {
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 28, color: LhColors.mute2),
              const SizedBox(height: 6),
              Text(
                '未找到匹配的合同',
                style: LhTypography.sans(
                    size: 12, color: LhColors.mute2, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text(
                '匹配 ${results.length} 项 · MATCHES',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.mute,
                  weight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 30),
            itemCount: results.length,
            itemBuilder: (ctx, i) => _buildResultCard(i, results[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(int i, SealApplication a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _SealApplicationDetailPage(app: a),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
            decoration: paperCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      a.id,
                      style: LhTypography.mono(
                        size: 8.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 8),
                    buildStatusChip(a.status),
                    const Spacer(),
                    Text(
                      a.amount == null ? '' : '${_fmtAmount(a.amount!)} 元',
                      style: LhTypography.mono(
                        size: 10.5,
                        color: LhColors.ink,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  a.partyB,
                  style: LhTypography.sans(
                    size: 12.5,
                    color: LhColors.ink,
                    weight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${a.contractType} · ${a.purpose}',
                  style: LhTypography.sans(
                    size: 9.5,
                    color: LhColors.mute,
                    weight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 借阅表单页 —— 生成带水印电子件 + 记录审计
//
//   访谈原文: "借阅要打水印。'仅供于平安银行使用，其他使用无效'"
//   系统实现:
//     · 表单填 借阅单位 → 水印动态字段
//     · 有效期 → 电子件下载链接过期时间
//     · 水印实时预览 (让用户看到最终效果)
//     · 提交后生成 BorrowRecord 入库审计 (谁 / 何时 / 单位 / 用途 / 下载次数)
// ═══════════════════════════════════════════════════════════════════════════

class _BorrowPage extends StatefulWidget {
  final SealApplication app;
  const _BorrowPage({required this.app});
  @override
  State<_BorrowPage> createState() => _BorrowPageState();
}

class _BorrowPageState extends State<_BorrowPage> {
  final _unitCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  String _medium = '电子件';
  int _validDays = 30;
  bool _validated = false;

  static const _mediums = ['电子件', '纸质件'];
  static const _dayOptions = [7, 15, 30, 60, 90];

  @override
  void dispose() {
    _unitCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _unitCtrl.text.trim().isNotEmpty && _purposeCtrl.text.trim().isNotEmpty;

  String get _autoId {
    final now = DateTime.now();
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'JY-$ymd-XXX';
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unitCtrl.text.trim().isEmpty ? '{借阅单位}' : _unitCtrl.text.trim();
    return Scaffold(
      backgroundColor: LhColors.paper,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFDF7), Color(0xFFEBE2CC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                child: Row(
                  children: [
                    buildBackButton(onTap: () => Navigator.of(context).pop()),
                    const Spacer(),
                    Text(
                      '发起借阅',
                      style: LhTypography.mono(
                        size: 8.5,
                        color: LhColors.mute2,
                        weight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Contract summary
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: heroPanelDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '借阅编号 · AUTO ID',
                              style: LhTypography.mono(
                                size: 8.5,
                                color: LhColors.mute,
                                weight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _autoId,
                              style: LhTypography.mono(
                                size: 14,
                                color: LhColors.ink,
                                weight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(height: 1, color: const Color(0xFFDDD5C0)),
                            const SizedBox(height: 10),
                            Text(
                              '合同 · CONTRACT',
                              style: LhTypography.mono(
                                size: 8.5,
                                color: LhColors.mute,
                                weight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.app.purpose,
                              style: LhTypography.sans(
                                size: 12.5,
                                color: LhColors.ink,
                                weight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.app.id}  ·  ${widget.app.partyB}',
                              style: LhTypography.mono(
                                size: 9,
                                color: LhColors.mute,
                                weight: FontWeight.w500,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionKicker('借阅信息 · BORROW INFO'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: paperCardDecoration(),
                        child: Column(
                          children: [
                            _inputField('借阅单位 *', _unitCtrl,
                                '接收方全称 (将用于水印动态字段)'),
                            const SizedBox(height: 12),
                            _inputField('借阅用途 *', _purposeCtrl,
                                '例: 授信审查 / 项目立项 / 尽调'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionKicker('借阅方式 · MEDIUM'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        decoration: paperCardDecoration(),
                        child: Row(
                          children: _mediums.map((m) {
                            final on = _medium == m;
                            return Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _medium = m),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: on
                                                ? LhColors.copper
                                                : LhColors.mute2,
                                            width: on ? 3 : 1,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        m,
                                        style: LhTypography.sans(
                                          size: 11.5,
                                          color: on
                                              ? LhColors.ink
                                              : LhColors.mute,
                                          weight: on
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      if (_medium == '电子件') ...[
                        const SizedBox(height: 20),
                        _sectionKicker('有效期 · VALIDITY'),
                        const SizedBox(height: 4),
                        Text(
                          '过期后下载链接自动失效, 防止越权传播',
                          style: LhTypography.sans(
                            size: 9.5,
                            color: LhColors.mute2,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                          decoration: paperCardDecoration(),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _dayOptions.map((d) {
                              final on = _validDays == d;
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _validDays = d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: on
                                        ? LhColors.copper.withAlpha(18)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: on
                                          ? LhColors.copper.withAlpha(140)
                                          : const Color(0xFFDDD5C0),
                                      width: 0.8,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '$d 天',
                                    style: LhTypography.mono(
                                      size: 10.5,
                                      color: on
                                          ? LhColors.copper
                                          : LhColors.mute,
                                      weight: on
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Watermark preview
                        _sectionKicker('水印预览 · WATERMARK PREVIEW'),
                        const SizedBox(height: 8),
                        _WatermarkPreview(
                          unit: unit,
                          contractSubject: widget.app.purpose,
                          validDays: _validDays,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Submit bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEFCF5),
                  border: Border(
                    top: BorderSide(color: Color(0xFFDDD5C0), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _canSubmit
                            ? '将生成带"$unit"水印的电子件'
                            : (_validated ? '⚠ 请补齐 * 必填项' : ''),
                        style: LhTypography.sans(
                          size: 10,
                          color: _validated && !_canSubmit
                              ? LhColors.neg
                              : LhColors.mute,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!_canSubmit) {
                          setState(() => _validated = true);
                          return;
                        }
                        final now = DateTime.now();
                        Navigator.of(context).pop(BorrowRecord(
                          id: _autoId,
                          borrowerUnit: _unitCtrl.text.trim(),
                          purpose: _purposeCtrl.text.trim(),
                          medium: _medium,
                          borrowedAt: now,
                          expiresAt: _medium == '电子件'
                              ? now.add(Duration(days: _validDays))
                              : now.add(const Duration(days: 365 * 100)),
                          applicant: '张伟',
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: _canSubmit ? LhColors.copper : LhColors.mute2,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '生成借阅件',
                              style: LhTypography.sans(
                                size: 12,
                                color: Colors.white,
                                weight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionKicker(String label) => Text(
        label,
        style: LhTypography.mono(
          size: 8.5,
          color: LhColors.mute,
          weight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );

  Widget _inputField(String label, TextEditingController ctrl, String hint) {
    final missing = _validated && ctrl.text.trim().isEmpty && label.endsWith('*');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LhTypography.sans(
            size: 10,
            color: missing ? LhColors.neg : LhColors.mute,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: LhTypography.sans(
            size: 12,
            color: LhColors.ink,
            weight: FontWeight.w600,
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: LhTypography.sans(
              size: 11,
              color: LhColors.mute2,
              weight: FontWeight.w500,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 5),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: missing ? LhColors.neg : const Color(0xFFDDD5C0),
                  width: 1),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: missing ? LhColors.neg : const Color(0xFFDDD5C0),
                  width: 1),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: LhColors.copper, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 水印预览组件 —— 模拟 PDF 页面 + 45° 平铺灰色斜印
// ═══════════════════════════════════════════════════════════════════════════

class _WatermarkPreview extends StatelessWidget {
  final String unit;
  final String contractSubject;
  final int validDays;
  const _WatermarkPreview({
    required this.unit,
    required this.contractSubject,
    required this.validDays,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDD5C0), width: 1),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0A0A0F),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            // Mock 合同文本 (fake 灰色横线)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contractSubject,
                    style: LhTypography.sans(
                      size: 11,
                      color: Colors.black87,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(
                    9,
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Container(
                        height: 5,
                        width: double.infinity * (i.isEven ? 0.9 : 0.8),
                        color: const Color(0xFFE0E0E0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Watermark 45° 平铺
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WatermarkPainter(text: '仅供 $unit 使用'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;
  _WatermarkPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.5); // ~ -28°
    canvas.translate(-size.width, -size.height);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF444444).withAlpha(38),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const dx = 180.0;
    const dy = 60.0;
    for (double y = 0; y < size.height * 2; y += dy) {
      for (double x = 0; x < size.width * 2; x += dx) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) => old.text != text;
}
