import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../meeting/native_meeting_detail_page.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';

const kProposalMeetingMinutesKey = 'meetingMinutes';

class ProposalMeetingMinute {
  const ProposalMeetingMinute({
    required this.meetingId,
    required this.title,
    this.meetingDate = '',
    this.organizer = '',
  });

  final int meetingId;
  final String title;
  final String meetingDate;
  final String organizer;

  String get label => title.trim().isEmpty ? '会议纪要 $meetingId' : title.trim();

  factory ProposalMeetingMinute.fromJson(Map<String, dynamic> json) {
    final raw = json['meetingId'] ?? json['id'];
    final id = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    return ProposalMeetingMinute(
      meetingId: id,
      title: '${json['title'] ?? ''}'.trim(),
      meetingDate: '${json['meetingDate'] ?? ''}'.trim(),
      organizer: '${json['organizer'] ?? ''}'.trim(),
    );
  }

  factory ProposalMeetingMinute.fromSummary(NativeMeetingSummary meeting) {
    return ProposalMeetingMinute(
      meetingId: meeting.meetingId,
      title: meeting.title.trim(),
      meetingDate: meeting.displayTime,
      organizer: meeting.organizerLabel,
    );
  }

  Map<String, dynamic> toJson() => {
    'meetingId': meetingId,
    'title': title,
    if (meetingDate.isNotEmpty) 'meetingDate': meetingDate,
    if (organizer.isNotEmpty) 'organizer': organizer,
  };
}

List<ProposalMeetingMinute> proposalMeetingMinutesOf(
  Map<String, dynamic> form,
) {
  final raw = form[kProposalMeetingMinutesKey];
  if (raw is! List) return const [];
  final out = <ProposalMeetingMinute>[];
  final seen = <int>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final minute = ProposalMeetingMinute.fromJson(
      Map<String, dynamic>.from(item),
    );
    if (minute.meetingId <= 0 || !seen.add(minute.meetingId)) continue;
    out.add(minute);
  }
  return out;
}

List<Map<String, dynamic>> proposalMeetingMinutesToJson(
  List<ProposalMeetingMinute> minutes,
) {
  return [for (final item in minutes) item.toJson()];
}

/// 销售提案「项目概况」里的会议纪要。通知最终人之前可绑定、解除，点开弹框看明细。
class ProposalMeetingMinutesBind extends StatelessWidget {
  const ProposalMeetingMinutesBind({
    super.key,
    required this.session,
    required this.minutes,
    required this.canEdit,
    required this.onChanged,
  });

  final AuthSession session;
  final List<ProposalMeetingMinute> minutes;
  final bool canEdit;
  final ValueChanged<List<ProposalMeetingMinute>> onChanged;

  Future<void> _open(BuildContext context, ProposalMeetingMinute minute) {
    return showNativeMeetingDetail(
      context: context,
      session: session,
      meetingId: minute.meetingId,
      asDialog: true,
    );
  }

  Future<void> _pick(BuildContext context) async {
    final next = await showDialog<List<ProposalMeetingMinute>>(
      context: context,
      builder: (ctx) =>
          _ProposalMeetingPicker(session: session, selected: minutes),
    );
    if (next == null) return;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final text = DunesColors.resolve(context, DunesColors.text);
    final muted = DunesColors.resolve(context, DunesColors.text3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '会议纪要',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              const Spacer(),
              if (canEdit)
                TextButton.icon(
                  onPressed: () => _pick(context),
                  icon: const Icon(Icons.add_link, size: 16),
                  label: Text(minutes.isEmpty ? '绑定会议纪要' : '调整绑定'),
                ),
            ],
          ),
          if (minutes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                canEdit ? '可绑定你主持的会议纪要，点开查看明细' : '未绑定',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            )
          else
            for (final minute in minutes)
              _MinuteRow(
                minute: minute,
                canEdit: canEdit,
                onOpen: () => _open(context, minute),
                onRemove: () => onChanged([
                  for (final item in minutes)
                    if (item.meetingId != minute.meetingId) item,
                ]),
              ),
        ],
      ),
    );
  }
}

class _MinuteRow extends StatelessWidget {
  const _MinuteRow({
    required this.minute,
    required this.canEdit,
    required this.onOpen,
    required this.onRemove,
  });

  final ProposalMeetingMinute minute;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (minute.meetingDate.isNotEmpty) minute.meetingDate,
      if (minute.organizer.isNotEmpty) minute.organizer,
    ].join(' · ');
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 18,
              color: DunesColors.resolve(context, const Color(0xFF3D6FD8)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    minute.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                ],
              ),
            ),
            if (canEdit)
              IconButton(
                tooltip: '解除绑定',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                size: 18,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProposalMeetingPicker extends StatefulWidget {
  const _ProposalMeetingPicker({required this.session, required this.selected});

  final AuthSession session;
  final List<ProposalMeetingMinute> selected;

  @override
  State<_ProposalMeetingPicker> createState() => _ProposalMeetingPickerState();
}

class _ProposalMeetingPickerState extends State<_ProposalMeetingPicker> {
  late final NativeMeetingService _service = NativeMeetingService(
    session: widget.session,
  );
  late List<ProposalMeetingMinute> _selected = [...widget.selected];
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<NativeMeetingSummary> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.fetchListPage(
        page: 0,
        size: 40,
        keyword: _query.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(error, fallback: '会议纪要加载失败');
        _loading = false;
      });
    }
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  bool _picked(int meetingId) =>
      _selected.any((item) => item.meetingId == meetingId);

  void _toggle(NativeMeetingSummary meeting) {
    setState(() {
      if (_picked(meeting.meetingId)) {
        _selected = [
          for (final item in _selected)
            if (item.meetingId != meeting.meetingId) item,
        ];
      } else {
        _selected = [..._selected, ProposalMeetingMinute.fromSummary(meeting)];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: size.height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '绑定会议纪要',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              Text(
                '选择你主持的会议纪要，可多选',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _query,
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索会议名称',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _body()),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text('确定（${_selected.length}）'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('没有可绑定的会议纪要'));
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final meeting = _items[index];
        final picked = _picked(meeting.meetingId);
        final summary = (meeting.summary ?? '').trim();
        return CheckboxListTile(
          value: picked,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (_) => _toggle(meeting),
          title: Text(
            meeting.title.trim().isEmpty
                ? '会议 ${meeting.meetingId}'
                : meeting.title.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (meeting.displayTime.isNotEmpty) meeting.displayTime,
              if (summary.isNotEmpty) summary,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
