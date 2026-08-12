import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'xflow_file_open.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_shared_widgets.dart';

const _kMaxCommentAttachments = 6;
const _kMaxCommentAttachmentBytes = 20 * 1024 * 1024;

/// 审批进度上方的讨论评论区（支持 @ 与楼中楼回复）。
class XfDetCommentsSection extends StatefulWidget {
  const XfDetCommentsSection({
    super.key,
    required this.service,
    required this.businessType,
    required this.businessId,
    this.fallbackPeople = const [],
  });

  final XflowService service;
  final String businessType;
  final int businessId;
  final List<ApprovalStakeholderPerson> fallbackPeople;

  @override
  State<XfDetCommentsSection> createState() => _XfDetCommentsSectionState();
}

class _XfDetCommentsSectionState extends State<XfDetCommentsSection> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  late final ConversationService _avatarService =
      ConversationService(session: widget.service.session);
  List<ApprovalCommentItem> _comments = const [];
  List<ApprovalStakeholderPerson> _people = const [];
  ApprovalCommentItem? _replyParent;
  final List<_PendingAttachment> _pendingAtts = [];
  final Map<String, Future<String>> _attUrlFutures = {};
  bool _loading = true;
  bool _sending = false;
  bool _picking = false;
  bool _dragging = false;
  String? _error;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 用于识别退格是否落在 @人名 内，整段删除。
  String _prevInputText = '';
  bool _applyingMentionDelete = false;

  /// @ 列表不包含自己。
  List<ApprovalStakeholderPerson> get _mentionablePeople {
    final selfId = widget.service.session.userId;
    if (selfId <= 0) return _people;
    return [
      for (final p in _people)
        if (p.id != selfId) p,
    ];
  }

  List<_CommentNode> get _roots => _buildCommentTree(_comments);

  @override
  void initState() {
    super.initState();
    _people = widget.fallbackPeople;
    _prevInputText = _input.text;
    _input.addListener(_onInputValueChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant XfDetCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessType != widget.businessType ||
        oldWidget.businessId != widget.businessId) {
      _load();
    }
  }

  @override
  void dispose() {
    _input.removeListener(_onInputValueChanged);
    _input.dispose();
    _focus.dispose();
    _avatarService.close();
    super.dispose();
  }

  void _onInputValueChanged() {
    if (_applyingMentionDelete) return;
    final prev = _prevInputText;
    final next = _input.value;
    _expandMentionDeleteIfNeeded(prev, next);
    _prevInputText = _input.text;
  }

  /// 退格/删除碰到 @人名 时，整段去掉（含紧随的空格）。
  void _expandMentionDeleteIfNeeded(String prev, TextEditingValue next) {
    if (next.text.length >= prev.length) return;
    if (!next.selection.isValid || !next.selection.isCollapsed) return;
    final composing = next.composing;
    if (composing.isValid && !composing.isCollapsed) return;

    final cursor = next.selection.baseOffset.clamp(0, next.text.length);
    final deletedLen = prev.length - next.text.length;
    if (deletedLen <= 0) return;
    final delStart = cursor;
    final delEnd = cursor + deletedLen;
    if (delStart < 0 || delEnd > prev.length) return;

    final ranges = _mentionRanges(prev);
    for (final r in ranges) {
      // 只在删到「@人名」本体时整段删；单独删尾随空格不触发。
      if (delStart < r.coreEnd && delEnd > r.start) {
        final newText = prev.substring(0, r.start) + prev.substring(r.end);
        _applyingMentionDelete = true;
        _input.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: r.start),
        );
        _applyingMentionDelete = false;
        return;
      }
    }
  }

  List<({int start, int coreEnd, int end})> _mentionRanges(String text) {
    final names = <String>{
      for (final p in _people)
        if (p.displayName.trim().isNotEmpty) p.displayName.trim(),
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final ranges = <({int start, int coreEnd, int end})>[];
    final occupied = <bool>[for (var i = 0; i < text.length; i++) false];
    for (final name in names) {
      final token = '@$name';
      var from = 0;
      while (from < text.length) {
        final idx = text.indexOf(token, from);
        if (idx < 0) break;
        final coreEnd = idx + token.length;
        final end =
            coreEnd < text.length && text[coreEnd] == ' ' ? coreEnd + 1 : coreEnd;
        var overlap = false;
        for (var i = idx; i < coreEnd; i++) {
          if (occupied[i]) {
            overlap = true;
            break;
          }
        }
        if (!overlap) {
          for (var i = idx; i < end && i < occupied.length; i++) {
            occupied[i] = true;
          }
          ranges.add((start: idx, coreEnd: coreEnd, end: end));
        }
        from = idx + 1;
      }
    }
    return ranges;
  }

  Future<void> _load() async {
    if (widget.businessId <= 0 || widget.businessType.trim().isEmpty) {
      setState(() {
        _loading = false;
        _comments = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final comments = await widget.service.fetchApprovalComments(
        businessType: widget.businessType,
        businessId: widget.businessId,
      );
      List<ApprovalStakeholderPerson> people = const [];
      try {
        people = await widget.service.fetchApprovalStakeholders(
          businessType: widget.businessType,
          businessId: widget.businessId,
        );
      } catch (_) {
        people = widget.fallbackPeople;
      }
      if (!mounted) return;
      setState(() {
        _comments = comments;
        if (people.isNotEmpty) _people = people;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<int> _parseMentionUserIds(String text) {
    final ids = <int>{};
    for (final p in _mentionablePeople) {
      final name = p.displayName.trim();
      if (name.isEmpty) continue;
      if (text.contains('@$name')) ids.add(p.id);
    }
    return ids.toList(growable: false);
  }

  Future<void> _pickMention() async {
    final people = _mentionablePeople;
    if (people.isEmpty) {
      showDunesToast(context, '暂无可 @ 的审批相关人');
      return;
    }
    final picked = await showModalBottomSheet<ApprovalStakeholderPerson>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  '选择要 @ 的人',
                  style: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: people.length,
                  itemBuilder: (_, i) {
                    final p = people[i];
                    return ListTile(
                      title: Text(p.displayName),
                      subtitle: p.role.isEmpty ? null : Text(p.role),
                      onTap: () => Navigator.pop(ctx, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _insertMentionName(picked.displayName.trim());
  }

  void _insertMentionName(String name) {
    if (name.isEmpty) return;
    final cur = _input.text;
    final sel = _input.selection;
    final insertAt = sel.isValid ? sel.baseOffset : cur.length;
    final safeAt = insertAt.clamp(0, cur.length);
    var before = cur.substring(0, safeAt);
    final after = cur.substring(safeAt);
    // 输入 @ 弹出选人后，复用已键入的 @，避免出现 @@人名。
    if (before.endsWith('@')) {
      before = before.substring(0, before.length - 1);
    }
    final needSpace =
        before.isNotEmpty && !before.endsWith(' ') && !before.endsWith('\n');
    final chunk = '${needSpace ? ' ' : ''}@$name ';
    final next = '$before$chunk$after';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: before.length + chunk.length),
    );
    _focus.requestFocus();
  }

  void _replyTo(ApprovalCommentItem c) {
    final selfId = widget.service.session.userId;
    final name = c.authorName.trim().isEmpty ? '用户' : c.authorName.trim();
    setState(() => _replyParent = c);
    if (c.authorUserId > 0 && c.authorUserId != selfId) {
      if (!_people.any((p) => p.id == c.authorUserId)) {
        setState(() {
          _people = [
            ..._people,
            ApprovalStakeholderPerson(id: c.authorUserId, displayName: name),
          ];
        });
      }
      if (!_input.text.contains('@$name')) {
        final cur = _input.text.trimRight();
        final mention = '@$name ';
        final next = cur.isEmpty ? mention : '$cur $mention';
        _input.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
    _focus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyParent = null);
    _focus.unfocus();
  }

  void _dismissKeyboard() {
    _focus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _pickAttachments() async {
    if (_picking || _sending) return;
    final remain = _kMaxCommentAttachments - _pendingAtts.length;
    if (remain <= 0) {
      showDunesToast(context, '附件最多 $_kMaxCommentAttachments 个');
      return;
    }
    setState(() => _picking = true);
    List<XFile> files = const [];
    try {
      files = await openFiles();
    } catch (_) {
      files = const [];
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (files.isEmpty || !mounted) return;
    await _addAttachmentFiles(files);
  }

  /// 选择/拖入共用：限制数量并在（macOS 安全作用域内）先读出字节再异步上传。
  Future<void> _addAttachmentFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    final remain = _kMaxCommentAttachments - _pendingAtts.length;
    if (remain <= 0) {
      showDunesToast(context, '附件最多 $_kMaxCommentAttachments 个');
      return;
    }
    var list = files;
    if (list.length > remain) {
      list = list.sublist(0, remain);
      showDunesToast(context, '附件最多 $_kMaxCommentAttachments 个，已截取前 $remain 个');
    }
    for (final f in list) {
      Uint8List bytes;
      try {
        bytes = await f.readAsBytes();
      } catch (_) {
        if (mounted) {
          showDunesToast(
            context,
            '无法读取「${f.name}」',
            kind: DunesToastKind.error,
          );
        }
        continue;
      }
      if (!mounted) return;
      unawaited(_uploadPendingBytes(f.name, bytes));
    }
  }

  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (_sending) return;
    setState(() => _dragging = false);
    final accessed = <Uint8List>[];
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        // macOS 沙盒：开启 security-scoped 访问，避免拖入后读文件失败。
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        if (mounted) showDunesToast(context, '请拖入文件（不支持文件夹）');
        return;
      }
      await _addAttachmentFiles(files);
    } finally {
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance
              .stopAccessingSecurityScopedResource(bookmark: bookmark);
        } catch (_) {}
      }
    }
  }

  Future<void> _uploadPendingBytes(String rawName, Uint8List bytes) async {
    if (!mounted) return;
    final name = rawName.trim().isEmpty ? '附件' : rawName.trim();
    if (bytes.length > _kMaxCommentAttachmentBytes) {
      showDunesToast(
        context,
        '「$name」超过 20MB，未添加',
        kind: DunesToastKind.error,
      );
      return;
    }
    final pending = _PendingAttachment(
      name: name,
      size: bytes.length,
      mimeType: lookupMimeType(name) ?? '',
    );
    setState(() => _pendingAtts.add(pending));
    try {
      final data = await widget.service.uploadProposalFile(
        bytes: bytes,
        fileName: name,
      );
      if (!mounted) return;
      final key = (data['objectKey'] ?? data['url'] ?? '').toString();
      setState(() {
        if (key.isEmpty) {
          pending
            ..status = _PendingStatus.error
            ..error = '上传失败';
        } else {
          pending
            ..status = _PendingStatus.done
            ..objectKey = key;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending
          ..status = _PendingStatus.error
          ..error = friendlyErrorText(e, fallback: '上传失败');
      });
    }
  }

  void _removePending(_PendingAttachment att) {
    setState(() => _pendingAtts.remove(att));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending) return;
    if (_pendingAtts.any((a) => a.status == _PendingStatus.uploading)) {
      showDunesToast(context, '附件上传中，请稍候');
      return;
    }
    final failed = _pendingAtts.where(
      (a) => a.status == _PendingStatus.error,
    );
    if (failed.isNotEmpty) {
      showDunesToast(
        context,
        '有附件上传失败，请移除后重试',
        kind: DunesToastKind.error,
      );
      return;
    }
    final attachments = [
      for (final a in _pendingAtts)
        if (a.status == _PendingStatus.done && a.objectKey.isNotEmpty)
          ApprovalCommentAttachment(
            name: a.name,
            objectKey: a.objectKey,
            size: a.size,
            mimeType: a.mimeType,
          ),
    ];
    if (text.isEmpty && attachments.isEmpty) return;
    final parentId = _replyParent?.id;
    setState(() => _sending = true);
    try {
      final created = await widget.service.postApprovalComment(
        businessType: widget.businessType,
        businessId: widget.businessId,
        text: text,
        mentionUserIds: _parseMentionUserIds(text),
        parentId: parentId,
        attachments: attachments,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, created];
        _input.clear();
        _replyParent = null;
        _pendingAtts.clear();
        _sending = false;
      });
      _dismissKeyboard();
      showDunesToast(context, '评论已发送，相关人将在审批助手收到通知');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showDunesToast(context, e.toString(), kind: DunesToastKind.error);
    }
  }

  String _authorOf(int? id) {
    if (id == null || id <= 0) return '';
    for (final x in _comments) {
      if (x.id == id) {
        return x.authorName.trim().isEmpty ? '用户' : x.authorName.trim();
      }
    }
    return '';
  }

  /// 预签名 URL 按 objectKey 缓存，避免评论列表重建时反复请求。
  Future<String> _attachmentUrl(ApprovalCommentAttachment att) {
    return _attUrlFutures.putIfAbsent(
      att.objectKey,
      () => widget.service.resolveFileUrl(att.toFileItem()),
    );
  }

  Future<void> _openAttachment(ApprovalCommentAttachment att) {
    return openXflowAttachment(
      context: context,
      service: widget.service,
      item: att.toFileItem(),
      preferPreview: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final replyName = _replyParent == null
        ? ''
        : (_replyParent!.authorName.trim().isEmpty
              ? '用户'
              : _replyParent!.authorName.trim());
    return XflowFormCard(
      title: '评论',
      tag: _loading ? '加载中' : '${_comments.length} 条',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: const Color(0xFFC44949),
                ),
              ),
            ),
          if (_loading && _comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_comments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: DunesColors.bgSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '暂无评论，可 @ 审批相关人讨论',
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text3,
                ),
              ),
            )
          else
            for (var i = 0; i < _roots.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1, color: DunesColors.borderSoft),
                ),
              _rootThread(_roots[i]),
            ],
          if (_replyParent != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: DunesColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 14, color: DunesColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '回复 $replyName',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.accentDeep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Text(
                      '取消',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _wrapDrop(Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            decoration: BoxDecoration(
              color: _dragging ? DunesColors.accentSoft : DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _dragging ? DunesColors.accent : DunesColors.borderSoft,
                width: _dragging ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_dragging)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Text(
                      '松开即可添加为评论附件',
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        color: DunesColors.accentDeep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_pendingAtts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final att in _pendingAtts)
                          _PendingAttachmentChip(
                            attachment: att,
                            onRemove:
                                _sending ? null : () => _removePending(att),
                          ),
                      ],
                    ),
                  ),
                Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    style: DunesTypography.sans(fontSize: 13, color: DunesColors.text),
                    decoration: InputDecoration(
                      hintText: _replyParent == null
                          ? '写评论，输入 @ 可提及相关人'
                          : '写回复…',
                      hintStyle: DunesTypography.sans(
                        fontSize: 13,
                        color: DunesColors.text3,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onTapOutside: (_) => _dismissKeyboard(),
                    onChanged: (v) {
                      if (v.endsWith('@')) {
                        _pickMention();
                      }
                    },
                  ),
                ),
                IconButton(
                  tooltip: '添加附件',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      (_sending || _picking) ? null : () => unawaited(_pickAttachments()),
                  icon: Icon(
                    Icons.attach_file_rounded,
                    size: 18,
                    color: DunesColors.accent,
                  ),
                ),
                IconButton(
                  tooltip: '@相关人',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _pickMention,
                  icon: Icon(
                    Icons.alternate_email_rounded,
                    size: 18,
                    color: DunesColors.accent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DunesColors.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _replyParent == null ? '发送' : '回复',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  /// PC / Web：输入框支持拖拽文件作为评论附件。
  Widget _wrapDrop(Widget child) {
    if (!_supportsDesktopDrop) return child;
    return DropTarget(
      onDragEntered: (_) {
        if (!_sending) setState(() => _dragging = true);
      },
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) => unawaited(_onDesktopDrop(detail)),
      child: child,
    );
  }

  Widget _rootThread(_CommentNode node) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _commentRow(node.comment, compact: false),
          if (node.children.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 40, top: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              decoration: BoxDecoration(
                color: DunesColors.bgSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DunesColors.borderSoft),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < node.children.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 12, color: DunesColors.borderSoft),
                    _replyBranch(node.children[i], depth: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _replyBranch(_CommentNode node, {required int depth}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _commentRow(node.comment, compact: true),
        for (final child in node.children)
          Padding(
            padding: EdgeInsets.only(left: (depth < 3 ? 12.0 : 0)),
            child: _replyBranch(child, depth: depth + 1),
          ),
      ],
    );
  }

  Widget _commentRow(ApprovalCommentItem c, {required bool compact}) {
    final name = c.authorName.trim().isEmpty ? '用户' : c.authorName.trim();
    final time = _formatCommentTime(c.createdAt);
    final parentAuthor = _authorOf(c.parentId);
    final showReplyTo =
        parentAuthor.isNotEmpty && parentAuthor != name;
    final avatarSize = compact ? 26.0 : 32.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ImUserAvatar(
          initial: name.isEmpty
              ? '?'
              : String.fromCharCodes(name.runes.take(1)),
          seed: c.authorUserId,
          size: avatarSize,
          borderRadius: avatarSize * 0.32,
          avatarPreset: c.authorAvatarPreset.isEmpty
              ? null
              : c.authorAvatarPreset,
          avatarObjectKey: c.authorAvatarObjectKey.isEmpty
              ? null
              : c.authorAvatarObjectKey,
          avatarService: _avatarService,
          fallbackBackground: DunesColors.accentSoft,
          fallbackForeground: DunesColors.accentDeep,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    name,
                    style: DunesTypography.sans(
                      fontSize: compact ? 12.5 : 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                  if (showReplyTo)
                    Text(
                      '回复 $parentAuthor',
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        color: DunesColors.text3,
                      ),
                    ),
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        color: DunesColors.text3,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (c.bodyText.trim().isNotEmpty)
                _MentionText(text: c.bodyText, people: _people),
              if (c.attachments.isNotEmpty) ...[
                const SizedBox(height: 6),
                _CommentAttachments(
                  attachments: c.attachments,
                  urlOf: _attachmentUrl,
                  onOpen: _openAttachment,
                ),
              ],
              const SizedBox(height: 2),
              GestureDetector(
                onTap: _sending ? null : () => _replyTo(c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '回复',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 始终展示本地年月日时分。
String _formatCommentTime(DateTime? at) {
  if (at == null) return '';
  final local = at.isUtc ? at.toLocal() : at;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)} '
      '${p(local.hour)}:${p(local.minute)}';
}

class _CommentNode {
  _CommentNode(this.comment);
  final ApprovalCommentItem comment;
  final List<_CommentNode> children = [];
}

List<_CommentNode> _buildCommentTree(List<ApprovalCommentItem> flat) {
  final nodes = <int, _CommentNode>{};
  for (final c in flat) {
    if (c.id <= 0) continue;
    nodes[c.id] = _CommentNode(c);
  }
  final roots = <_CommentNode>[];
  for (final c in flat) {
    final node = nodes[c.id];
    if (node == null) continue;
    final pid = c.parentId;
    if (pid != null && pid > 0 && nodes.containsKey(pid) && pid != c.id) {
      nodes[pid]!.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

enum _PendingStatus { uploading, done, error }

class _PendingAttachment {
  _PendingAttachment({
    required this.name,
    required this.size,
    required this.mimeType,
  });

  final String name;
  final int size;
  final String mimeType;
  _PendingStatus status = _PendingStatus.uploading;
  String objectKey = '';
  String error = '';
}

String _fmtAttachmentSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final _PendingAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final att = attachment;
    final isError = att.status == _PendingStatus.error;
    final size = _fmtAttachmentSize(att.size);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFE7B3B3) : DunesColors.borderSoft,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (att.status == _PendingStatus.uploading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            )
          else
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.insert_drive_file_outlined,
              size: 14,
              color: isError ? const Color(0xFFC44949) : DunesColors.text3,
            ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              att.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 11.5,
                color: isError ? const Color(0xFFC44949) : DunesColors.text2,
              ),
            ),
          ),
          if (size.isNotEmpty && !isError) ...[
            const SizedBox(width: 4),
            Text(
              size,
              style: DunesTypography.sans(
                fontSize: 10.5,
                color: DunesColors.text3,
              ),
            ),
          ],
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: DunesColors.text3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentAttachments extends StatelessWidget {
  const _CommentAttachments({
    required this.attachments,
    required this.urlOf,
    required this.onOpen,
  });

  final List<ApprovalCommentAttachment> attachments;
  final Future<String> Function(ApprovalCommentAttachment) urlOf;
  final Future<void> Function(ApprovalCommentAttachment) onOpen;

  @override
  Widget build(BuildContext context) {
    final images = [for (final a in attachments) if (a.isImage) a];
    final files = [for (final a in attachments) if (!a.isImage) a];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final att in images) _imageThumb(att),
            ],
          ),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
        for (var i = 0; i < files.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _fileRow(files[i]),
        ],
      ],
    );
  }

  Widget _imageThumb(ApprovalCommentAttachment att) {
    return GestureDetector(
      onTap: () => onOpen(att),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 72,
          height: 72,
          child: FutureBuilder<String>(
            future: urlOf(att),
            builder: (context, snap) {
              final url = snap.data ?? '';
              if (url.isEmpty) {
                return Container(
                  color: DunesColors.bgSoft,
                  alignment: Alignment.center,
                  child: snap.connectionState == ConnectionState.waiting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        )
                      : const Icon(
                          Icons.broken_image_outlined,
                          size: 20,
                          color: DunesColors.text3,
                        ),
                );
              }
              return Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: DunesColors.bgSoft,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: DunesColors.text3,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fileRow(ApprovalCommentAttachment att) {
    final size = _fmtAttachmentSize(att.size);
    return GestureDetector(
      onTap: () => onOpen(att),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file_outlined,
              size: 15,
              color: DunesColors.text3,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                att.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: const Color(0xFF3B7BB5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (size.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                size,
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MentionText extends StatelessWidget {
  const _MentionText({required this.text, required this.people});

  final String text;
  final List<ApprovalStakeholderPerson> people;

  @override
  Widget build(BuildContext context) {
    final names = people
        .map((e) => e.displayName.trim())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final base = DunesTypography.sans(
      fontSize: 13,
      height: 1.45,
      color: DunesColors.text2,
    );
    if (names.isEmpty) {
      return Text(text, style: base);
    }
    final pattern = RegExp(
      names.map(RegExp.escape).map((n) => '@$n').join('|'),
    );
    final spans = <TextSpan>[];
    var start = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: const TextStyle(
            color: Color(0xFF3B7BB5),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(text: TextSpan(style: base, children: spans));
  }
}
