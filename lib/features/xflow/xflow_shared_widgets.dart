import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'proposal_upload_config.dart';
import 'xflow_approval_flow_ui.dart';
import 'xflow_form_styles.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

/// 提交审批前的二次确认。
Future<bool> confirmSubmitForApproval(
  BuildContext context, {
  String title = '确认提交审批',
  String? message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message ?? '提交后将进入审批流程，请确认信息填写完整准确。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认提交'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 代发起人确认发起前的二次确认。
Future<bool> confirmInitiateProposal(BuildContext context) {
  return confirmSubmitForApproval(
    context,
    message: '确认后将进入推送人的审批流程，提案状态不可撤回。\n\n请再次核对表单内容是否完整准确。',
  );
}

/// B1 / B14 / P1 暖紫居中 hero-stat（与 index.html 1:1）
class XflowHeroStatCard extends StatelessWidget {
  const XflowHeroStatCard({
    super.key,
    required this.kicker,
    required this.badgeText,
    required this.bigValue,
    required this.bigUnit,
    required this.footItems,
    this.badgeUrge = false,
    this.warmStyle = true,
    this.colors = const <Color>[],
  });

  final String kicker;
  final String badgeText;
  final String bigValue;
  final String bigUnit;
  final List<(String label, String value, String? tone)> footItems;
  final bool badgeUrge;
  final bool warmStyle;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    if (warmStyle) return _warmHero();
    return _darkHero();
  }

  Widget _warmHero() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
          colors: [Color(0xFFF7F1E8), Color(0xFFEBE3F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: DunesColors.accentLine),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF553B96).withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 2),
            spreadRadius: -8,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        children: [
          Column(
            children: [
              Text(
                kicker,
                textAlign: TextAlign.center,
                style: DunesTypography.mono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.06 * 9.5,
                  color: DunesColors.accentDeep,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DunesColors.coralSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badgeText,
                  style: DunesTypography.mono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.coral,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: bigValue,
                  style: DunesTypography.sans(
                    fontSize: 34,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.03 * 34,
                    color: DunesColors.accentDeep,
                  ),
                ),
                TextSpan(
                  text: bigUnit,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: DunesColors.text2,
                  ),
                ),
              ],
            ),
          ),
          if (footItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: const Color(0xFF7E64BD).withValues(alpha: 0.18),
                  ),
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < footItems.length; i++) ...[
                    Expanded(child: _WarmFootItem(item: footItems[i])),
                    if (i != footItems.length - 1) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _darkHero() {
    final gradientColors = colors.isNotEmpty
        ? colors
        : const <Color>[
            Color(0xFF1B3A3F),
            Color(0xFF2F5D62),
            Color(0xFF5F8B8F),
          ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kicker,
                  style: DunesTypography.mono(
                    fontSize: 9,
                    color: Colors.white70,
                    letterSpacing: 0.06 * 9,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badgeText,
                  style: DunesTypography.mono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: bigValue,
                  style: DunesTypography.sans(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.8,
                  ),
                ),
                TextSpan(
                  text: bigUnit,
                  style: DunesTypography.sans(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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

class _WarmFootItem extends StatelessWidget {
  const _WarmFootItem({required this.item});

  final (String label, String value, String? tone) item;

  @override
  Widget build(BuildContext context) {
    Color valueColor = DunesColors.text;
    if (item.$3 == 'pos') valueColor = DunesColors.green;
    if (item.$3 == 'urge' || item.$3 == 'neg') valueColor = DunesColors.coral;
    return Column(
      children: [
        Text(
          item.$1,
          textAlign: TextAlign.center,
          style: DunesTypography.sans(
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          item.$2,
          textAlign: TextAlign.center,
          style: DunesTypography.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class XflowSectionLabel extends StatelessWidget {
  const XflowSectionLabel({
    super.key,
    required this.accent,
    required this.title,
    this.trailing,
  });

  final String accent;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          accent,
          style: DunesTypography.sans(
            color: DunesColors.accentDeep,
            fontSize: 10.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          ' · $title',
          style: DunesTypography.sans(
            color: DunesColors.text2,
            fontSize: 10.8,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Divider(height: 1, color: DunesColors.borderSoft),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: DunesTypography.sans(
              fontSize: 9.5,
              color: DunesColors.text3,
            ),
          ),
      ],
    );
  }
}

/// cond-chip 筛选（mono 10px + 圆点）
class XflowStatusChip extends StatelessWidget {
  const XflowStatusChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.showDot = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? DunesColors.text : DunesColors.bgApp,
          border: Border.all(
            color: active ? DunesColors.text : DunesColors.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: active ? Colors.white : DunesColors.text2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: DunesTypography.mono(
                fontSize: 10,
                letterSpacing: 0.02 * 10,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : DunesColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class XflowWfListSearch extends StatelessWidget {
  const XflowWfListSearch({
    super.key,
    required this.controller,
    required this.hint,
  });

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: DunesColors.text3),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: controller,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class XflowProposalListCard extends StatelessWidget {
  const XflowProposalListCard({
    super.key,
    required this.item,
    required this.onTap,
    this.mode = XflowListCardMode.b1,
    this.showTrackButton = false,
    this.onTrackTap,
    this.onDeleteDraft,
  });

  final XflowProposalItem item;
  final VoidCallback onTap;
  final XflowListCardMode mode;
  final bool showTrackButton;
  final VoidCallback? onTrackTap;
  final VoidCallback? onDeleteDraft;

  @override
  Widget build(BuildContext context) {
    if (mode == XflowListCardMode.b14) {
      return _buildCompactInitiatedCard(context);
    }
    if (mode == XflowListCardMode.b1 || mode == XflowListCardMode.p1) {
      return _buildCompactApprovalCard(context);
    }
    final prog = _progressFoot(item);
    final typePill = item.tag1 ?? item.txType ?? '';
    return Material(
      color: DunesColors.bgApp,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: DunesTypography.sans(
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.005 * 13,
                                ),
                              ),
                            ),
                            if (typePill.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: DunesColors.bgSoft,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  typePill,
                                  style: DunesTypography.mono(
                                    fontSize: 9,
                                    color: DunesColors.text2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.code} · ${_proposalTypeLabel(item)}',
                          style: DunesTypography.mono(
                            fontSize: 10,
                            color: DunesColors.text3,
                            letterSpacing: 0.04 * 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: item.status),
                ],
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 9,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (mode == XflowListCardMode.b1 &&
                      item.createdByName.isNotEmpty)
                    Text(
                      '提交人 ${item.createdByName}',
                      style: DunesTypography.sans(
                        fontSize: 10,
                        color: DunesColors.text2,
                      ),
                    ),
                  if (item.createdAt != null)
                    Text(
                      _formatShortDate(item.createdAt!),
                      style: DunesTypography.sans(
                        fontSize: 10,
                        color: DunesColors.text2,
                      ),
                    ),
                  if (item.scaleWan != null && item.scaleWan!.isNotEmpty)
                    Text(
                      '¥${item.scaleWan}万',
                      style: DunesTypography.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text2,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Container(
                padding: const EdgeInsets.only(top: 7),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: DunesColors.borderSoft),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: prog.pct / 100,
                                minHeight: 4,
                                backgroundColor: DunesColors.bgCard,
                                color: DunesColors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            prog.px,
                            style: DunesTypography.mono(
                              fontSize: 9.5,
                              color: DunesColors.text2,
                              letterSpacing: 0.02 * 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '→ ${prog.hint}',
                      style: DunesTypography.sans(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.accent,
                        letterSpacing: 0.02 * 9,
                      ),
                    ),
                    if (showTrackButton) ...[
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: onTrackTap,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '流程追踪',
                          style: DunesTypography.sans(
                            fontSize: 9.5,
                            color: DunesColors.accent,
                          ),
                        ),
                      ),
                    ],
                    if (onDeleteDraft != null) ...[
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: onDeleteDraft,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '删除',
                          style: DunesTypography.sans(
                            fontSize: 9.5,
                            color: DunesColors.coral,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「我发起的」列表：名称、提案种类、提案编码、提案类型、时间。
  Widget _buildCompactInitiatedCard(BuildContext context) {
    final code = item.code.trim().isEmpty ? '#${item.id}' : item.code.trim();
    final kindLabel = proposalKindLabel(
      templateKey: item.templateKey,
      businessType: item.businessType,
    );
    final typeLabel = _compactProposalTypeLabel(item, kindLabel);
    final title = _compactApprovalTitle(item, kindLabel);
    final timeText = item.createdAt != null
        ? _formatShortDate(item.createdAt!)
        : '—';
    return Material(
      color: DunesColors.bgApp,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01 * 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: item.status),
                ],
              ),
              const SizedBox(height: 8),
              _compactMetaRow('提案种类', kindLabel),
              const SizedBox(height: 4),
              _compactMetaRow('提案编码', code, mono: true),
              const SizedBox(height: 4),
              _compactMetaRow('提案类型', typeLabel),
              const SizedBox(height: 4),
              _compactMetaRow('时间', timeText),
              if (onDeleteDraft != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDeleteDraft,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '删除草稿',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.coral,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 「我审批的 / 抄送」紧凑列表：含彩色提案状态。
  Widget _buildCompactApprovalCard(BuildContext context) {
    final code = item.code.trim().isEmpty ? '#${item.id}' : item.code.trim();
    final kindLabel = proposalKindLabel(
      templateKey: item.templateKey,
      businessType: item.businessType,
    );
    final typeLabel = _compactProposalTypeLabel(item, kindLabel);
    final title = _compactApprovalTitle(item, kindLabel);
    final timeText = item.createdAt != null
        ? _formatShortDate(item.createdAt!)
        : '—';
    final submitter = item.createdByName.trim();
    return Material(
      color: DunesColors.bgApp,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01 * 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: item.status),
                ],
              ),
              const SizedBox(height: 8),
              _compactMetaRow('提案种类', kindLabel),
              const SizedBox(height: 4),
              _compactMetaRow('提案编码', code, mono: true),
              const SizedBox(height: 4),
              _compactMetaRow('提案类型', typeLabel),
              if (mode == XflowListCardMode.b1 && submitter.isNotEmpty) ...[
                const SizedBox(height: 4),
                _compactMetaRow('提交人', submitter),
              ],
              const SizedBox(height: 4),
              _compactMetaRow('时间', timeText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactMetaRow(
    String label,
    String value, {
    bool mono = false,
    String? status,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
        ),
        Expanded(
          child: status != null && status.trim().isNotEmpty
              ? Align(
                  alignment: Alignment.centerRight,
                  child: _StatusBadge(status: status),
                )
              : Text(
                  value,
                  textAlign: TextAlign.right,
                  style: mono
                      ? DunesTypography.mono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text2,
                        )
                      : DunesTypography.sans(
                          fontSize: 11.5,
                          color: DunesColors.text2,
                        ),
                ),
        ),
      ],
    );
  }
}

enum XflowListCardMode { b1, b14, p1 }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final st = status.toUpperCase();
    Color bg;
    Color fg;
    if (st == 'OPEN' || st == 'PENDING') {
      bg = DunesColors.amberSoft;
      fg = const Color(0xFF5D3508);
    } else if (st == 'APPROVED' || st == 'DONE' || st == 'LIVE') {
      bg = DunesColors.greenSoft;
      fg = const Color(0xFF085041);
    } else if (st == 'REJECTED') {
      bg = DunesColors.coralSoft;
      fg = const Color(0xFF993C1D);
    } else if (st == 'DRAFT' || st == 'PENDING_INITIATE') {
      bg = DunesColors.blueSoft;
      fg = DunesColors.blue;
    } else if (st == 'VOIDED') {
      bg = DunesColors.bgSoft;
      fg = DunesColors.text3;
    } else if (st == 'SUPERSEDED') {
      bg = DunesColors.bgSoft;
      fg = DunesColors.text2;
    } else {
      bg = DunesColors.bgSoft;
      fg = DunesColors.text2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _statusText(st),
        style: DunesTypography.mono(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: fg,
          letterSpacing: 0.04 * 9,
        ),
      ),
    );
  }
}

class XflowDsBar extends StatelessWidget {
  const XflowDsBar({
    super.key,
    required this.crumb,
    required this.title,
    required this.onBack,
    this.onMore,
  });

  final String crumb;
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: const BoxDecoration(
        color: XfProposalUi.bg,
        border: Border(bottom: BorderSide(color: XfProposalUi.line)),
      ),
      child: Row(
        children: [
          _CircleIconButton(onPressed: onBack, icon: Icons.chevron_left),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  crumb,
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    color: XfProposalUi.mute2,
                    letterSpacing: 0.04 * 9.5,
                  ),
                ),
                Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: XfProposalUi.ink,
                    letterSpacing: -0.005 * 14,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (onMore != null)
            _CircleIconButton(
              onPressed: onMore!,
              icon: Icons.more_horiz,
              filled: false,
            ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.onPressed,
    required this.icon,
    this.filled = true,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? XfProposalUi.cardAlt : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 16,
            color: filled ? XfProposalUi.ink : XfProposalUi.mute,
          ),
        ),
      ),
    );
  }
}

class XflowFormCard extends StatelessWidget {
  const XflowFormCard({
    super.key,
    required this.title,
    required this.child,
    this.tag,
  });

  final String title;
  final Widget child;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: XfProposalUi.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: XfProposalUi.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: XfProposalUi.ink,
                  ),
                ),
              ),
              if (tag != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: XfProposalUi.coralSoft,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFFFD6C8)),
                  ),
                  child: Text(
                    tag!,
                    style: DunesTypography.mono(
                      fontSize: 9,
                      color: XfProposalUi.coral,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class XflowStageList extends StatelessWidget {
  const XflowStageList({
    super.key,
    required this.stages,
    this.layout = const {},
    this.onStageHelp,
    this.userNames = const {},
  });

  final List<Map<String, dynamic>> stages;
  final Map<String, dynamic> layout;
  final Future<void> Function(int stageIndex)? onStageHelp;
  final Map<int, String> userNames;

  @override
  Widget build(BuildContext context) {
    return XflowApprovalFlowSection(
      stages: stages,
      layout: layout,
      onStageHelp: onStageHelp,
      userNames: userNames,
      topSpacing: 0,
      showHeader: false,
    );
  }
}

// Legacy stage list helpers removed — visuals live in xflow_approval_flow_ui.dart.

String ccTriggerTypeLabel(dynamic t) {
  switch ('${t ?? ''}'.toLowerCase()) {
    case 'always':
      return '始终抄送';
    case 'task_level':
      return '按任务等级';
    case 'need_advance':
      return '涉及垫资';
    case 'monthly_scale_gt':
      return '月规模超阈值';
    case 'invoice_tax':
      return '税务成本';
    default:
      final s = '$t';
      return s.isEmpty ? '条件触发' : s;
  }
}

/// 抄送规则单行 — WebView `.xf-det-cc-row` 1:1
class XfCcRuleRow extends StatelessWidget {
  const XfCcRuleRow({super.key, required this.rule, this.showDivider = true});

  final Map<String, dynamic> rule;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final who = (rule['title'] ?? rule['userName'] ?? '—').toString();
    final meta = [
      if (rule['roleLabel'] != null && rule['roleLabel'].toString().isNotEmpty)
        rule['roleLabel'].toString(),
      if (rule['deptLabel'] != null && rule['deptLabel'].toString().isNotEmpty)
        rule['deptLabel'].toString(),
    ].join(' · ');
    final trigger = ccTriggerTypeLabel(rule['triggerType']);
    final tpl = (rule['reasonTpl'] ?? '').toString();
    final reasonLine = tpl.isNotEmpty ? '$trigger · $tpl' : trigger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            who,
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DunesColors.text,
              height: 1.35,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              [if (meta.isNotEmpty) meta, reasonLine].join(' · '),
              style: DunesTypography.sans(
                fontSize: 10,
                color: DunesColors.text3,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class XflowCcRulesCard extends StatefulWidget {
  const XflowCcRulesCard({
    super.key,
    required this.rules,
    this.loading = false,
    this.error,
    this.hideWhenEmpty = true,
  });

  final List<Map<String, dynamic>> rules;
  final bool loading;
  final String? error;

  /// WebView：规则加载成功且为空时隐藏整张卡片
  final bool hideWhenEmpty;

  @override
  State<XflowCcRulesCard> createState() => _XflowCcRulesCardState();
}

class _XflowCcRulesCardState extends State<XflowCcRulesCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.hideWhenEmpty &&
        !widget.loading &&
        widget.rules.isEmpty &&
        widget.error == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: XfProposalUi.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: XfProposalUi.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '抄送规则说明',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: XfProposalUi.ink,
                    letterSpacing: -0.005 * 13,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '提交后按规则自动知会相关人员',
                    style: DunesTypography.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: XfProposalUi.mute2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: XfProposalUi.mute2,
                  ),
                ),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            if (widget.loading)
              Text(
                '加载抄送规则…',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: XfProposalUi.mute2,
                ),
              )
            else if (widget.error != null)
              Text(
                widget.error!,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: XfProposalUi.coral,
                ),
              )
            else if (widget.rules.isEmpty)
              Text(
                '暂无抄送规则配置',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: XfProposalUi.mute2,
                ),
              )
            else
              for (var i = 0; i < widget.rules.length; i++)
                XfCcRuleRow(
                  rule: widget.rules[i],
                  showDivider: i < widget.rules.length - 1,
                ),
          ],
        ],
      ),
    );
  }
}

class XflowXfActionBar extends StatelessWidget {
  const XflowXfActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.secondaryDanger = false,
    this.onDisabledTap,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final bool secondaryDanger;
  final VoidCallback? onDisabledTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final resolvedIcon = icon ??
        (label.contains('撤回') ? Icons.undo_rounded : Icons.check_rounded);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (secondaryLabel != null && onSecondaryPressed != null) ...[
            OutlinedButton(
              onPressed: loading ? null : onSecondaryPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: secondaryDanger
                    ? XfProposalUi.coral
                    : XfProposalUi.mute,
                side: BorderSide(
                  color: secondaryDanger
                      ? XfProposalUi.coral.withValues(alpha: 0.45)
                      : XfProposalUi.line,
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(
                secondaryLabel!,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Material(
            color: Colors.transparent,
            child: XflowApprovalSubmitButton(
              onPressed: onPressed,
              loading: loading,
              enabled: onPressed != null,
              label: label == '重新提交' ? '提交审批' : label,
              onDisabledTap: onDisabledTap,
              icon: resolvedIcon,
            ),
          ),
        ],
      ),
    );
  }
}

class XflowProposalHero extends StatelessWidget {
  const XflowProposalHero({super.key, required this.detail});

  final XflowProposalDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF7A5E9F), Color(0xFFB073A7), Color(0xFFC38D95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'PROPOSAL · 销售提案',
                style: DunesTypography.mono(
                  color: Colors.white70,
                  fontSize: 9.2,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _pill('SALES'),
              _pill(_statusText(detail.status)),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            detail.title,
            style: DunesTypography.sans(
              color: Colors.white,
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _metaItem('beaconId', detail.beaconId)),
              const SizedBox(width: 8),
              Expanded(child: _metaItem('owner', detail.ownerName)),
              const SizedBox(width: 8),
              Expanded(
                child: _metaItem(
                  'amount',
                  detail.amountText.isEmpty ? '—' : detail.amountText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: DunesTypography.mono(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .65),
            fontSize: 8,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value.isEmpty ? '—' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DunesTypography.sans(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class XflowProductCard extends StatelessWidget {
  const XflowProductCard({super.key, required this.product});

  final XflowProduct product;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: DunesColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 16,
              color: DunesColors.accentDeep,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name.isEmpty ? '未命名产品' : product.name,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (product.platformProductId.isNotEmpty)
                  Text(
                    'platformProductId: ${product.platformProductId}',
                    style: DunesTypography.sans(
                      fontSize: 9.5,
                      color: DunesColors.text3,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            product.ratio.isEmpty ? '—' : product.ratio,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class XflowSlotGrid extends StatelessWidget {
  const XflowSlotGrid({super.key, required this.slots});

  final List<XflowSettlementSlot> slots;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DunesColors.border),
        ),
        child: Text(
          '暂无协议槽位',
          style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
        ),
      );
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: slots.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.38,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, index) {
        final slot = slots[index];
        return Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DunesColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'SEQ ${slot.seq == 0 ? index + 1 : slot.seq}',
                    style: DunesTypography.mono(
                      fontSize: 9,
                      color: DunesColors.text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    slot.slotType,
                    style: DunesTypography.mono(
                      fontSize: 8.5,
                      color: DunesColors.accentDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                slot.name.isEmpty ? '未命名槽位' : slot.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                slot.ratio.isEmpty ? '—' : slot.ratio,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text2,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final tag in slot.tags.take(2))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: DunesColors.bgSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        tag,
                        style: DunesTypography.sans(
                          fontSize: 8.5,
                          color: DunesColors.text2,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressFoot {
  const _ProgressFoot({
    required this.pct,
    required this.px,
    required this.hint,
  });

  final int pct;
  final String px;
  final String hint;
}

_ProgressFoot _progressFoot(XflowProposalItem item) {
  final st = item.status.toUpperCase();
  var pct = 25;
  var px = st == 'PENDING_INITIATE' ? '待发起' : '草稿';
  var hint = st == 'DRAFT' ? '继续填写' : '查看详情';
  if (st == 'PENDING' && item.totalSteps > 0) {
    pct = ((item.currentStep / item.totalSteps) * 100).round().clamp(0, 95);
    px = '${item.currentStep}/${item.totalSteps} 步';
  } else if (st == 'APPROVED') {
    pct = 100;
    px = '待合同';
  } else if (st == 'LIVE') {
    pct = 100;
    px = '已上线';
  } else if (st == 'REJECTED') {
    pct = 100;
    px = '已驳回';
    hint = '查看驳回原因 · 可重新填写';
  } else if (st != 'DRAFT' && st != 'PENDING_INITIATE') {
    pct = 60;
    px = '已提交';
  }
  if (item.scaleWan != null && item.scaleWan!.isNotEmpty) {
    hint = '¥${item.scaleWan}万';
  }
  return _ProgressFoot(pct: pct, px: px, hint: hint);
}

String _compactApprovalTitle(XflowProposalItem item, String kindLabel) {
  final businessType = item.businessType.trim();
  final rawTitle = item.title.trim();
  final isGenericSubmissionTitle =
      rawTitle.isEmpty ||
      rawTitle == businessType ||
      rawTitle.startsWith('$businessType #');
  final templateName =
      item.businessType.toUpperCase() == 'PROPOSAL' || isGenericSubmissionTitle
      ? kindLabel
      : rawTitle;
  final submitter = item.createdByName.trim();
  return submitter.isEmpty ? templateName : '$submitter - $templateName';
}

String _compactProposalTypeLabel(XflowProposalItem item, String kindLabel) {
  final proposalType = excelProposalTypeLabel(item.proposalType);
  if (proposalType != '—') return proposalType;
  return item.businessType.toUpperCase() == 'PROPOSAL' ? '—' : kindLabel;
}

String _proposalTypeLabel(XflowProposalItem item) {
  if (item.proposalType != null && item.proposalType!.trim().isNotEmpty) {
    return item.proposalType!.trim();
  }
  if (item.txType != null && item.txType!.isNotEmpty) return item.txType!;
  if (item.businessType.toUpperCase() == 'CONTRACT_SEAL') return '合同用印';
  return '销售提案';
}

String _formatShortDate(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

String _statusText(String status) {
  final raw = status.toUpperCase();
  if (raw == 'OPEN' || raw == 'PENDING') return '审批中';
  if (raw == 'APPROVED') return '已通过';
  if (raw == 'DONE') return '已完成';
  if (raw == 'LIVE') return '已上线';
  if (raw == 'REJECTED') return '已驳回';
  if (raw == 'DRAFT') return '草稿';
  if (raw == 'PENDING_INITIATE') return '待发起';
  if (raw == 'VOIDED') return '已作废';
  if (raw == 'SUPERSEDED') return '已替代';
  return raw.isEmpty ? '未知状态' : raw;
}

/// 推送目标（确认推送后返回）。
class XflowPushTarget {
  const XflowPushTarget({
    required this.userId,
    required this.name,
    required this.message,
  });

  final int userId;
  final String name;
  final String message;
}

/// 「推送给同事」选人弹窗：仅在运营推送白名单内选择（可本地搜索过滤）。
/// 返回所选同事与附言；用户取消则返回 null。
Future<XflowPushTarget?> showXflowPushSheet({
  required BuildContext context,
  required XflowService service,
  String subtitle = '在运营推送白名单同事中选择，对方可代为填写并确认发起',
  List<Map<String, dynamic>> suggested = const <Map<String, dynamic>>[],
}) {
  return showModalBottomSheet<XflowPushTarget>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DunesColors.bgApp,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => _XflowPushSheetBody(
      service: service,
      subtitle: subtitle,
      suggested: suggested,
    ),
  );
}

class _XflowPushSheetBody extends StatefulWidget {
  const _XflowPushSheetBody({
    required this.service,
    required this.subtitle,
    required this.suggested,
  });

  final XflowService service;
  final String subtitle;
  final List<Map<String, dynamic>> suggested;

  @override
  State<_XflowPushSheetBody> createState() => _XflowPushSheetBodyState();
}

class _XflowPushSheetBodyState extends State<_XflowPushSheetBody> {
  final _searchController = TextEditingController();
  final _messageController = TextEditingController(text: '请确认后发起');
  late final List<Map<String, dynamic>> _whitelist;
  List<Map<String, dynamic>> _results = const <Map<String, dynamic>>[];
  int _selectedId = 0;
  String _selectedName = '';

  @override
  void initState() {
    super.initState();
    final selfId = widget.service.session.userId;
    _whitelist = widget.suggested
        .map(_normalizeUser)
        .where((u) => (u['userId'] as int) > 0 && u['userId'] != selfId)
        .toList(growable: false);
    _results = _whitelist;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _normalizeUser(Map<dynamic, dynamic> raw) {
    final uid = _toInt(raw['userId'] ?? raw['id']);
    final name =
        (raw['displayName'] ?? raw['userName'] ?? raw['name'] ?? '用户#$uid')
            .toString();
    final dept =
        (raw['departmentName'] ?? raw['department'] ?? raw['dept'] ?? '')
            .toString();
    return <String, dynamic>{
      'userId': uid,
      'displayName': name,
      'departmentName': dept,
    };
  }

  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  void _onQueryChanged(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = _whitelist);
      return;
    }
    setState(() {
      _results = _whitelist
          .where((u) {
            final name = (u['displayName'] ?? '').toString().toLowerCase();
            final dept = (u['departmentName'] ?? '').toString().toLowerCase();
            return name.contains(q) || dept.contains(q);
          })
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '推送给同事',
            style: DunesTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.subtitle,
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _onQueryChanged,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: DunesTypography.sans(
              fontSize: 12.5,
              color: DunesColors.text,
            ),
            decoration: InputDecoration(
              hintText: '搜索白名单同事',
              hintStyle: DunesTypography.sans(
                fontSize: 12.5,
                color: DunesColors.text3,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: DunesColors.text3,
              ),
              isDense: true,
              filled: true,
              fillColor: DunesColors.bgSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            child: _buildResults(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _messageController,
            minLines: 1,
            maxLines: 3,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: DunesTypography.sans(
              fontSize: 12.5,
              color: DunesColors.text,
            ),
            decoration: InputDecoration(
              labelText: '附言（可选）',
              labelStyle: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
              isDense: true,
              filled: true,
              fillColor: DunesColors.bgSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _selectedId <= 0
                ? null
                : () {
                    final msg = _messageController.text.trim();
                    Navigator.pop(
                      context,
                      XflowPushTarget(
                        userId: _selectedId,
                        name: _selectedName,
                        message: msg.isEmpty ? '请确认后发起' : msg,
                      ),
                    );
                  },
            child: Text(_selectedId <= 0 ? '请选择同事' : '确认推送给 $_selectedName'),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_whitelist.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '运营推送白名单暂无人员，请先在管理台配置',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '白名单内无匹配同事',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final u = _results[i];
        final uid = u['userId'] as int;
        final name = (u['displayName'] ?? '').toString();
        final dept = (u['departmentName'] ?? '').toString();
        return ListTile(
          dense: true,
          selected: _selectedId == uid,
          title: Text(
            dept.isNotEmpty ? '$name · $dept' : name,
            style: DunesTypography.sans(fontSize: 12.5),
          ),
          trailing: _selectedId == uid
              ? const Icon(
                  Icons.check_circle,
                  size: 18,
                  color: DunesColors.accent,
                )
              : null,
          onTap: () => setState(() {
            _selectedId = uid;
            _selectedName = name;
          }),
        );
      },
    );
  }
}
