import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../kb/native_kb_models.dart';
import '../meeting/native_meeting_models.dart';
import 'nova_web_storage.dart';

String novaPrdPendingStorageKey(int convId) => 'dunes_nova_prd_pending_$convId';

class NovaPrdPendingJob {
  const NovaPrdPendingJob({
    required this.at,
    required this.meetingId,
    required this.prdModel,
    required this.userMsgId,
    required this.assistantMsgId,
    required this.messageText,
    required this.kbFileName,
    required this.kbTitle,
    required this.prdFileName,
    required this.meetingTitle,
    this.minutesMarkdown = '',
    this.minutesFileName = '',
    this.sendStarted = false,
  });

  final int at;
  final int meetingId;
  final String prdModel;
  final int userMsgId;
  final int assistantMsgId;
  final String messageText;
  /// 知识库中的会议纪要文件名（NOVA 通过 RAG 引用）。
  final String kbFileName;
  final String kbTitle;
  /// NOVA 生成后落盘的 PRD 文件名。
  final String prdFileName;
  final String meetingTitle;
  @Deprecated('Legacy PRD flow: inline markdown attachment')
  final String minutesMarkdown;
  @Deprecated('Legacy PRD flow: inline markdown attachment')
  final String minutesFileName;
  /// 已对 NOVA/`/ai/assistant/messages` 发起请求；再进会话不得重发。
  final bool sendStarted;

  bool get expired =>
      DateTime.now().millisecondsSinceEpoch - at > 15 * 60 * 1000;

  NovaPrdPendingJob copyWith({bool? sendStarted}) {
    return NovaPrdPendingJob(
      at: at,
      meetingId: meetingId,
      prdModel: prdModel,
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      messageText: messageText,
      kbFileName: kbFileName,
      kbTitle: kbTitle,
      prdFileName: prdFileName,
      meetingTitle: meetingTitle,
      minutesMarkdown: minutesMarkdown,
      minutesFileName: minutesFileName,
      sendStarted: sendStarted ?? this.sendStarted,
    );
  }

  factory NovaPrdPendingJob.fromJson(Map<String, dynamic> json) {
    final legacyMinutesFile =
        (json['minutesFileName'] ?? json['prdFileName'] ?? '').toString();
    final kbFileName = (json['kbFileName'] ?? legacyMinutesFile).toString();
    final kbTitle = (json['kbTitle'] ?? json['meetingTitle'] ?? '').toString();
    return NovaPrdPendingJob(
      at: (json['at'] as num?)?.toInt() ?? 0,
      meetingId: (json['meetingId'] as num?)?.toInt() ?? 0,
      prdModel: (json['prdModel'] ?? '').toString(),
      userMsgId: (json['userMsgId'] as num?)?.toInt() ?? 0,
      assistantMsgId: (json['assistantMsgId'] as num?)?.toInt() ?? 0,
      messageText: (json['messageText'] ?? '').toString(),
      kbFileName: kbFileName,
      kbTitle: kbTitle,
      prdFileName: (json['prdFileName'] ?? '').toString(),
      meetingTitle: (json['meetingTitle'] ?? '').toString(),
      minutesMarkdown: (json['minutesMarkdown'] ?? '').toString(),
      minutesFileName: legacyMinutesFile,
      sendStarted: json['sendStarted'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at,
        'meetingId': meetingId,
        'prdModel': prdModel,
        'userMsgId': userMsgId,
        'assistantMsgId': assistantMsgId,
        'messageText': messageText,
        'kbFileName': kbFileName,
        'kbTitle': kbTitle,
        'prdFileName': prdFileName,
        'meetingTitle': meetingTitle,
        'sendStarted': sendStarted,
      };
}

Future<void> persistNovaPrdPendingJob({
  required int userId,
  required int conversationId,
  required NovaPrdPendingJob job,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  await NovaWebStorage.merge(userId, <String, dynamic>{
    novaPrdPendingStorageKey(conversationId): jsonEncode(job.toJson()),
  });
}

Future<void> clearNovaPrdPendingJob({
  required int userId,
  required int conversationId,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  final merged = await NovaWebStorage.load(userId);
  merged.remove(novaPrdPendingStorageKey(conversationId));
  await NovaWebStorage.save(userId, Map<String, dynamic>.from(merged));
}

NovaPrdPendingJob? readNovaPrdPendingJob(
  Map<String, String> storage,
  int convId,
) {
  if (convId <= 0) return null;
  final raw = storage[novaPrdPendingStorageKey(convId)];
  if (raw == null || raw.isEmpty) return null;
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final job = NovaPrdPendingJob.fromJson(Map<String, dynamic>.from(json));
    if (job.expired) return null;
    return job;
  } catch (_) {
    return null;
  }
}

/// 会话气泡展示：精确指向知识库文档。
String buildMeetingPrdDisplayText(String kbFileName) {
  final name = kbFileName.trim();
  if (name.isEmpty) return '请基于知识库中的会议纪要生成 PRD 文件。';
  return '请基于知识库文档「$name」生成 PRD 文件。';
}

/// 发给 NOVA 的指令：引用知识库文件，由 NOVA 调用知识库生成可下载 PRD。
String buildMeetingPrdNovaMessage({
  required String kbFileName,
  required String prdFileName,
}) {
  final source = kbFileName.trim().isNotEmpty ? kbFileName.trim() : '会议纪要';
  final target = prdFileName.trim().isNotEmpty ? prdFileName.trim() : 'PRD.md';
  return '请基于知识库中的文档「$source」，生成一份完整的产品需求文档（PRD），'
      '并输出为可下载的文件「$target」。'
      'PRD 需包含：背景与目标、用户与场景、功能需求（分模块）、非功能需求、验收标准、里程碑/排期建议。'
      '内容应基于该会议纪要提炼，不要编造与会议无关的业务；信息不足处标注「待补充」。';
}

Future<T?> _showNovaPrdBottomSheet<T>({
  required BuildContext context,
  required String title,
  required Widget body,
  Widget? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.borderSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                ),
              ),
              body,
              if (footer != null) footer,
            ],
          ),
        ),
      );
    },
  );
}

Future<NativeMeetingSummary?> showMeetingMinutesPickerDialog(
  BuildContext context, {
  required List<NativeMeetingSummary> meetings,
}) {
  final selectable = meetings.toList(growable: false);

  return _showNovaPrdBottomSheet<NativeMeetingSummary>(
    context: context,
    title: '选择会议纪要',
    body: selectable.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DunesColors.bgApp,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.cloud_off_outlined,
                    size: 26,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '暂无可用于生成 PRD 的会议纪要',
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '请先在会议纪要详情页上传至知识库，并等待索引完成后再试',
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.58,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              itemCount: selectable.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final row = selectable[i];
                final title = row.title.trim().isNotEmpty
                    ? row.title.trim()
                    : '未命名会议';
                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx, row),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: DunesColors.bgApp,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.description_outlined,
                              size: 18,
                              color: DunesColors.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: DunesTypography.sans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.text,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  row.displayTime,
                                  style: DunesTypography.sans(
                                    fontSize: 11,
                                    color: DunesColors.text3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '知识库已索引',
                                  style: DunesTypography.sans(
                                    fontSize: 10,
                                    color: DunesColors.accentDeep,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: DunesColors.text3.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: DunesColors.text2,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: const Text('取消'),
        ),
      ),
    ),
  );
}

Future<NativeKbDocument?> showKbDocumentPickerDialog(
  BuildContext context, {
  required List<NativeKbDocument> documents,
}) {
  final selectable = documents
      .where(nativeKbDocumentIndexed)
      .toList(growable: false);

  return _showNovaPrdBottomSheet<NativeKbDocument>(
    context: context,
    title: '选择知识库文档',
    body: selectable.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DunesColors.bgApp,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.cloud_off_outlined,
                    size: 26,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '暂无已索引的知识库文档',
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '请先在知识库上传会议纪要等文档，并等待索引完成后再试',
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.58,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              itemCount: selectable.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final row = selectable[i];
                final title = row.title.trim().isNotEmpty
                    ? row.title.trim()
                    : (row.fileName.trim().isNotEmpty
                          ? row.fileName.trim()
                          : '未命名文档');
                final subtitle = row.fileName.trim().isNotEmpty &&
                        row.fileName.trim() != title
                    ? row.fileName.trim()
                    : row.statusLabel;
                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx, row),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: DunesColors.bgApp,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.menu_book_outlined,
                              size: 18,
                              color: DunesColors.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: DunesTypography.sans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.text,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DunesTypography.sans(
                                      fontSize: 12,
                                      color: DunesColors.text3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: DunesColors.text3,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

Future<bool> showMeetingPrdConfirmDialog(
  BuildContext context, {
  required String meetingTitle,
  required String modelName,
}) {
  return _showNovaPrdBottomSheet<bool>(
    context: context,
    title: '生成 PRD 文档',
    body: Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DunesColors.bgApp,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meetingTitle,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.memory, size: 14, color: DunesColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      modelName,
                      style: DunesTypography.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.accentDeep,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '将基于已上传且完成索引的知识库文档，由 NOVA 生成可下载的 PRD 文件。',
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.text2,
              height: 1.55,
            ),
          ),
        ],
      ),
    ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: DunesColors.text2,
                side: const BorderSide(color: DunesColors.borderSoft),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF553B96), Color(0xFF7B5CB8)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Center(
                      child: Text(
                        '确认生成',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ).then((v) => v == true);
}
