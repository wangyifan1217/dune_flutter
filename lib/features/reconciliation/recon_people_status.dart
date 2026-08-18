import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'recon_audit_record.dart';
import 'reconciliation_shucai_models.dart';

Future<void> showReconEveryoneStatusSheet({
  required BuildContext context,
  required String asOfDate,
  required List<ReconSectorPeopleAck> sectors,
  ConversationService? avatarService,
}) {
  final body = ReconEveryoneStatusPane(
    asOfDate: asOfDate,
    sectors: sectors,
    avatarService: avatarService,
  );
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: body,
    ),
  );
}

class ReconEveryoneStatusPane extends StatelessWidget {
  const ReconEveryoneStatusPane({
    super.key,
    required this.asOfDate,
    required this.sectors,
    this.avatarService,
  });

  final String asOfDate;
  final List<ReconSectorPeopleAck> sectors;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sectors.length == 1 ? '审核人状态' : '全部审核状态',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${shucaiDisplayDate(asOfDate)}${sectors.length == 1 ? ' · ${sectors.first.title}' : ''}',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < sectors.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _sectorBlock(sectors[i]),
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

  Widget _sectorBlock(ReconSectorPeopleAck sector) {
    final total = sector.people.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total <= 0
              ? '${sector.title}  ·  暂无核对人'
              : '${sector.title}  ·  ${sector.confirmedCount}/$total 已确认',
          style: DunesTypography.sans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DunesColors.text,
          ),
        ),
        if (total <= 0) ...[
          const SizedBox(height: 8),
          Text(
            '该板块还没有配置核对人。',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
        ] else ...[
          for (final step in reconAuditChainSteps)
            ..._layerRows(sector.people.where((e) => e.step == step).toList()),
        ],
      ],
    );
  }

  List<Widget> _layerRows(List<ReconPeopleAckEntry> people) {
    if (people.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Text(
        reconChainStepLabel(people.first.step),
        style: DunesTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DunesColors.text3,
        ),
      ),
      const SizedBox(height: 6),
      for (final item in people) ...[
        _personRow(item),
        const SizedBox(height: 6),
      ],
    ];
  }

  Widget _personRow(ReconPeopleAckEntry item) {
    final person = item.person;
    final name = person.displayName;
    final initial = name.isEmpty ? '审' : name.substring(0, 1);
    final avatar = reconResolvedUserAvatar(
      userId: person.userId,
      preset: person.avatarPreset,
      objectKey: person.avatarObjectKey,
    );
    final time = reconFormatDecidedAt(item.decidedAt);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            ImUserAvatar(
              initial: initial,
              seed: person.userId,
              size: 32,
              avatarPreset: avatar.preset,
              avatarObjectKey: avatar.objectKey,
              avatarUrl: avatar.url,
              avatarService: avatarService,
              borderRadius: 9,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  if (time.isNotEmpty)
                    Text(
                      '确认时间  $time',
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text2,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              item.confirmed ? '已确认' : '待确认',
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: item.confirmed ? DunesColors.green : DunesColors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showReconUnmatchedSheet({
  required BuildContext context,
  required String title,
  required List<ReconUnmatchedSlot> unmatched,
}) {
  final body = ReconUnmatchedPane(title: title, unmatched: unmatched);
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => body,
  );
}

class ReconUnmatchedPane extends StatelessWidget {
  const ReconUnmatchedPane({
    super.key,
    required this.title,
    required this.unmatched,
  });

  final String title;
  final List<ReconUnmatchedSlot> unmatched;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '未匹配 / 未分配人员',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$title · 以下姓名未对上组织人员，或该层尚未分配',
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final step in reconAuditChainSteps)
                      ..._stepBlock(
                        unmatched.where((e) => e.step.toUpperCase() == step).toList(),
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

  List<Widget> _stepBlock(List<ReconUnmatchedSlot> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(
          reconChainStepLabel(items.first.step),
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DunesColors.coral,
          ),
        ),
      ),
      for (final item in items) ...[
        _row(item),
        const SizedBox(height: 6),
      ],
    ];
  }

  Widget _row(ReconUnmatchedSlot item) {
    final name = item.name.trim().isEmpty ? '未匹配' : item.name.trim();
    final countHint = item.count > 1 ? '  · ${item.count} 行' : '';
    final isL2 = item.step.toUpperCase() == reconChainL2;
    final label = item.unassigned
        ? (isL2 ? '本板块未分配' : (item.count > 0 ? '未填写  ${item.count} 行' : '未填写'))
        : '未匹配  $name$countHint';
    final loc = item.location;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DunesColors.coralSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.coral.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DunesColors.coral,
              ),
            ),
            if (loc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  loc,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
