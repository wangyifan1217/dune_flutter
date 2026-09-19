import '../auth/auth_session.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_inbox_cache.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../drive/native_drive_service.dart';
import '../kb/native_kb_service.dart';
import '../meeting/native_meeting_service.dart';
import '../proposal_intake/proposal_intake_service.dart';
import '../tasks/task_api.dart';
import '../xflow/approval_list_cache.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import 'global_search_models.dart';

typedef GlobalSearchEmit = void Function(GlobalSearchSnapshot snapshot);

class GlobalSearchFacade {
  GlobalSearchFacade({required this.session})
    : _contacts = ContactService(session: session),
      _conversations = ConversationService(session: session),
      _xflow = XflowService(session: session),
      _proposals = ProposalIntakeService(session: session),
      _tasks = TaskApi(session),
      _kb = NativeKbService(session: session),
      _drive = NativeDriveService(session: session),
      _meetings = NativeMeetingService(session: session);

  final AuthSession session;
  final ContactService _contacts;
  final ConversationService _conversations;
  final XflowService _xflow;
  final ProposalIntakeService _proposals;
  final TaskApi _tasks;
  final NativeKbService _kb;
  final NativeDriveService _drive;
  final NativeMeetingService _meetings;

  static const sourceTimeout = Duration(milliseconds: 2500);
  static const inboxTtl = Duration(seconds: 45);
  static const allPreviewLimit = 3;
  static const deepPageSize = 20;

  static List<XflowProposalItem>? _inboxItems;
  static DateTime? _inboxAt;
  static int? _inboxUserId;

  int _seq = 0;
  GlobalSearchSnapshot _latest = const GlobalSearchSnapshot(
    seq: 0,
    query: '',
    tab: GlobalSearchCategory.all,
    groups: {},
  );

  int get seq => _seq;

  void cancel() => _seq++;

  int nextSeq() => ++_seq;

  Future<void> search({
    required String query,
    required GlobalSearchCategory tab,
    String messageKind = '',
    String approvalFilter = '',
    required GlobalSearchEmit emit,
  }) async {
    final seq = nextSeq();
    final q = query.trim();
    var snap = GlobalSearchSnapshot(
      seq: seq,
      query: q,
      tab: tab,
      groups: {
        for (final c in GlobalSearchCategory.values)
          if (c != GlobalSearchCategory.all)
            c: GlobalSearchGroupState(
              category: c,
              status: GlobalSearchGroupStatus.loading,
            ),
      },
      queryHint: queryHint(q) ?? '',
    );
    _emit(seq, snap, emit);

    await _runLocalWave(seq: seq, query: q, tab: tab, emit: emit);
    if (seq != _seq) return;

    await _runContacts(seq: seq, query: q, tab: tab, emit: emit);
    if (seq != _seq) return;

    final runMessages =
        q.isNotEmpty &&
        (q.length >= 2 ||
            _hasIdeograph(q) ||
            tab == GlobalSearchCategory.messages);
    final runOtherWave2 =
        q.length >= 2 ||
        (tab.isWave2 && tab != GlobalSearchCategory.messages && q.isNotEmpty);
    if (!runMessages && !runOtherWave2) {
      _markSkippedWave2(seq, emit);
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (seq != _seq) return;
      final current = _latest;
      if (current.seq != seq || current.slowHint) return;
      final anyNetwork = current.groups.values.any(
        (g) =>
            g.category != GlobalSearchCategory.apps &&
            g.status == GlobalSearchGroupStatus.ready,
      );
      if (!anyNetwork) {
        _emit(seq, _latest.copyWithSlowHint(true), emit);
      }
    });

    final jobs = <Future<void>>[];
    if (runMessages && _shouldFetch(tab, GlobalSearchCategory.messages)) {
      jobs.add(
        _runMessages(
          seq: seq,
          query: q,
          tab: tab,
          kind: messageKind,
          emit: emit,
        ),
      );
    }
    if (runOtherWave2 && _shouldFetch(tab, GlobalSearchCategory.approvals)) {
      jobs.add(
        _runApprovals(
          seq: seq,
          query: q,
          tab: tab,
          filter: approvalFilter,
          emit: emit,
        ),
      );
    }
    if (runOtherWave2 && _shouldFetch(tab, GlobalSearchCategory.tasks)) {
      jobs.add(_runTasks(seq: seq, query: q, tab: tab, emit: emit));
    }
    if (runOtherWave2 && _shouldFetch(tab, GlobalSearchCategory.documents)) {
      jobs.add(_runDocuments(seq: seq, query: q, tab: tab, emit: emit));
    }
    if (runOtherWave2 && _shouldFetch(tab, GlobalSearchCategory.meetings)) {
      jobs.add(_runMeetings(seq: seq, query: q, tab: tab, emit: emit));
    }
    await Future.wait(jobs);
    if (!runOtherWave2) {
      _markSkippedWave2(
        seq,
        emit,
        except: const {GlobalSearchCategory.messages},
      );
    }
  }

  Future<void> retry({
    required GlobalSearchCategory category,
    required String query,
    required GlobalSearchCategory tab,
    String messageKind = '',
    String approvalFilter = '',
    required GlobalSearchEmit emit,
  }) async {
    final seq = _seq;
    if (seq <= 0) return;
    _patch(
      seq,
      category,
      GlobalSearchGroupState(
        category: category,
        status: GlobalSearchGroupStatus.loading,
      ),
      emit,
    );
    switch (category) {
      case GlobalSearchCategory.contacts:
        await _runContacts(seq: seq, query: query, tab: tab, emit: emit);
      case GlobalSearchCategory.groups:
        await _runLocalWave(seq: seq, query: query, tab: tab, emit: emit);
      case GlobalSearchCategory.messages:
        await _runMessages(
          seq: seq,
          query: query,
          tab: tab,
          kind: messageKind,
          emit: emit,
        );
      case GlobalSearchCategory.approvals:
        await _runApprovals(
          seq: seq,
          query: query,
          tab: tab,
          filter: approvalFilter,
          emit: emit,
        );
      case GlobalSearchCategory.tasks:
        await _runTasks(seq: seq, query: query, tab: tab, emit: emit);
      case GlobalSearchCategory.documents:
        await _runDocuments(seq: seq, query: query, tab: tab, emit: emit);
      case GlobalSearchCategory.meetings:
        await _runMeetings(seq: seq, query: query, tab: tab, emit: emit);
      case GlobalSearchCategory.apps:
        await _runLocalWave(seq: seq, query: query, tab: tab, emit: emit);
      case GlobalSearchCategory.all:
        break;
    }
  }

  List<NativeConversation> recentContacts({int limit = 6}) {
    final rows = _localConversations();
    final out = <NativeConversation>[];
    for (final c in rows) {
      if (!c.isPrivate || c.isSelfMemo) continue;
      if ((c.peerUserId ?? 0) <= 0) continue;
      out.add(c);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<GlobalSearchHit> recentApps({int limit = 6}) {
    return _appCatalog().take(limit).map(_appHit).toList(growable: false);
  }

  static String? queryHint(String query) {
    final q = query.trim();
    if (q.isEmpty) return null;
    final wan = RegExp(r'(\d+(?:\.\d+)?)\s*万').firstMatch(q);
    if (wan != null) {
      final n = double.tryParse(wan.group(1) ?? '') ?? 0;
      if (n > 0) {
        final raw = (n * 10000).round();
        final formatted = raw.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
        return '约等于 $formatted';
      }
    }
    final upper = q.toUpperCase();
    if (upper.startsWith('SP-') || upper.startsWith('PROP-')) {
      return '优先匹配提案编号';
    }
    return null;
  }

  Future<void> _runLocalWave({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required GlobalSearchEmit emit,
  }) async {
    final convos = _localConversations();
    final q = query.toLowerCase();
    var groups = convos.where((c) {
      if (!c.isGroup && !c.isWorkgroupApproval) return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) ||
          c.displayTitle.toLowerCase().contains(q);
    }).toList();

    if (q.isNotEmpty && groups.length < 3) {
      try {
        final remote = await _withTimeout(
          _conversations.fetchConversations(query: query),
        );
        final seen = groups.map((c) => c.id).toSet();
        for (final c in remote) {
          if (!c.isGroup && !c.isWorkgroupApproval) continue;
          if (!seen.add(c.id)) continue;
          if (c.title.toLowerCase().contains(q) ||
              c.displayTitle.toLowerCase().contains(q)) {
            groups.add(c);
          }
        }
      } catch (_) {}
    }

    final groupHits = groups.map(_conversationHit).toList(growable: false);
    _patch(
      seq,
      GlobalSearchCategory.groups,
      GlobalSearchGroupState(
        category: GlobalSearchCategory.groups,
        status: GlobalSearchGroupStatus.ready,
        items: _limit(groupHits, tab, GlobalSearchCategory.groups),
        total: groupHits.length,
      ),
      emit,
    );

    final apps = _appCatalog().where((app) {
      if (q.isEmpty) return true;
      return app.title.toLowerCase().contains(q) ||
          app.subtitle.toLowerCase().contains(q);
    }).toList();
    final appHits = apps.map(_appHit).toList(growable: false);
    _patch(
      seq,
      GlobalSearchCategory.apps,
      GlobalSearchGroupState(
        category: GlobalSearchCategory.apps,
        status: GlobalSearchGroupStatus.ready,
        items: _limit(appHits, tab, GlobalSearchCategory.apps),
        total: appHits.length,
      ),
      emit,
    );

    if (q.isNotEmpty) {
      final privateHits = convos
          .where((c) => c.isPrivate && !c.isSelfMemo)
          .where(
            (c) =>
                c.displayTitle.toLowerCase().contains(q) ||
                (c.peerDepartment ?? '').toLowerCase().contains(q),
          )
          .map(_conversationAsContactHit)
          .toList(growable: false);
      if (privateHits.isNotEmpty) {
        final existing = _latest.group(GlobalSearchCategory.contacts);
        if (existing.items.isEmpty) {
          _patch(
            seq,
            GlobalSearchCategory.contacts,
            GlobalSearchGroupState(
              category: GlobalSearchCategory.contacts,
              status: GlobalSearchGroupStatus.loading,
              items: _limit(privateHits, tab, GlobalSearchCategory.contacts),
              total: privateHits.length,
            ),
            emit,
          );
        }
      }
    }

    if (q.isNotEmpty) {
      final previewHits = _previewMessageHits(convos, q);
      if (previewHits.isNotEmpty) {
        _patch(
          seq,
          GlobalSearchCategory.messages,
          GlobalSearchGroupState(
            category: GlobalSearchCategory.messages,
            status: GlobalSearchGroupStatus.loading,
            items: _limit(previewHits, tab, GlobalSearchCategory.messages),
            total: previewHits.length,
          ),
          emit,
        );
      }
    }
  }

  Future<void> _runContacts({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required GlobalSearchEmit emit,
  }) async {
    if (query.isEmpty) {
      _patch(
        seq,
        GlobalSearchCategory.contacts,
        const GlobalSearchGroupState(
          category: GlobalSearchCategory.contacts,
          status: GlobalSearchGroupStatus.ready,
        ),
        emit,
      );
      return;
    }
    try {
      final org = await _withTimeout(
        _contacts.fetchOrgContacts(keyword: query),
      );
      List<NativeContact> external = const [];
      try {
        external = await _withTimeout(
          _contacts.fetchExternalContacts(keyword: query),
        );
      } catch (_) {}
      final seen = <int>{};
      final hits = <GlobalSearchHit>[];
      for (final c in [...org.searchItems, ...external]) {
        if (c.userId <= 0 || c.userId == session.userId) continue;
        if (!seen.add(c.userId)) continue;
        hits.add(_contactHit(c));
      }
      _patch(
        seq,
        GlobalSearchCategory.contacts,
        GlobalSearchGroupState(
          category: GlobalSearchCategory.contacts,
          status: GlobalSearchGroupStatus.ready,
          items: _limit(hits, tab, GlobalSearchCategory.contacts),
          total: hits.length,
        ),
        emit,
      );
    } catch (e) {
      _fail(seq, GlobalSearchCategory.contacts, e, emit);
    }
  }

  Future<void> _runMessages({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required String kind,
    required GlobalSearchEmit emit,
  }) async {
    try {
      final rows = await _withTimeout(
        _conversations.searchMessagesGlobal(
          query: query,
          kind: kind,
          limit: tab == GlobalSearchCategory.messages ? 80 : 40,
        ),
        duration: const Duration(milliseconds: 6000),
      );
      final seeded = _latest.group(GlobalSearchCategory.messages).items;
      final merged = _mergeMessageRows(rows, seeded);
      var hits = _groupMessageHits(merged);
      try {
        hits = await _withTimeout(
          _enrichThreadCounts(hits, query: query, kind: kind),
          duration: const Duration(milliseconds: 4000),
        );
      } catch (_) {}
      if (seq != _seq) return;
      _patch(
        seq,
        GlobalSearchCategory.messages,
        GlobalSearchGroupState(
          category: GlobalSearchCategory.messages,
          status: GlobalSearchGroupStatus.ready,
          items: _limit(hits, tab, GlobalSearchCategory.messages),
          total: hits.length,
        ),
        emit,
      );
    } catch (e) {
      _fail(seq, GlobalSearchCategory.messages, e, emit);
    }
  }

  Future<void> _runApprovals({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required String filter,
    required GlobalSearchEmit emit,
  }) async {
    try {
      final inbox = await _inbox(force: false);
      final q = query.toLowerCase();
      var rows = inbox.where((item) {
        final hay =
            '${item.title} ${item.code} ${item.createdByName} ${item.status}'
                .toLowerCase();
        return hay.contains(q);
      }).toList();
      if (filter.isNotEmpty) {
        rows = rows.where((item) {
          final st = item.status.toUpperCase();
          return switch (filter) {
                'pending' => item.isPending,
                'mine' => true,
                'done' => !item.isPending,
                _ => true,
              } &&
              (filter != 'mine' || st.isNotEmpty);
        }).toList();
      }
      final hits = <GlobalSearchHit>[...rows.map(_approvalHit)];
      try {
        final intakes = await _withTimeout(
          _proposals.fetchList(keyword: query, pageSize: 12),
        );
        for (final row in intakes.items) {
          hits.add(_intakeHit(row));
        }
      } catch (_) {}
      _patch(
        seq,
        GlobalSearchCategory.approvals,
        GlobalSearchGroupState(
          category: GlobalSearchCategory.approvals,
          status: GlobalSearchGroupStatus.ready,
          items: _limit(hits, tab, GlobalSearchCategory.approvals),
          total: hits.length,
        ),
        emit,
      );
    } catch (e) {
      _fail(seq, GlobalSearchCategory.approvals, e, emit);
    }
  }

  Future<void> _runTasks({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required GlobalSearchEmit emit,
  }) async {
    try {
      final page = await _withTimeout(
        _tasks.listTasksPage(
          q: query,
          size: tab == GlobalSearchCategory.tasks ? deepPageSize : 8,
        ),
      );
      final hits = page.items.map(_taskHit).toList(growable: false);
      _patch(
        seq,
        GlobalSearchCategory.tasks,
        GlobalSearchGroupState(
          category: GlobalSearchCategory.tasks,
          status: GlobalSearchGroupStatus.ready,
          items: _limit(hits, tab, GlobalSearchCategory.tasks),
          total: page.total > 0 ? page.total : hits.length,
        ),
        emit,
      );
    } catch (e) {
      _fail(seq, GlobalSearchCategory.tasks, e, emit);
    }
  }

  Future<void> _runDocuments({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required GlobalSearchEmit emit,
  }) async {
    try {
      final size = tab == GlobalSearchCategory.documents ? deepPageSize : 6;
      final kbFuture = _withTimeout(
        _kb.listDocuments(keyword: query, size: size),
      );
      final driveFuture = _searchDrive(query, size);
      final kb = await kbFuture;
      List<GlobalSearchHit> driveHits = const [];
      try {
        driveHits = await driveFuture;
      } catch (_) {}
      final hits = <GlobalSearchHit>[...kb.items.map(_kbHit), ...driveHits];
      _patch(
        seq,
        GlobalSearchCategory.documents,
        GlobalSearchGroupState(
          category: GlobalSearchCategory.documents,
          status: GlobalSearchGroupStatus.ready,
          items: _limit(hits, tab, GlobalSearchCategory.documents),
          total: kb.total + driveHits.length,
        ),
        emit,
      );
    } catch (e) {
      _fail(seq, GlobalSearchCategory.documents, e, emit);
    }
  }

  Future<List<GlobalSearchHit>> _searchDrive(String query, int size) async {
    final spaces = await _withTimeout(_drive.fetchSpaces());
    if (spaces.isEmpty) return const [];
    final hits = <GlobalSearchHit>[];
    for (final space in spaces.take(4)) {
      try {
        final items = await _withTimeout(
          _drive.fetchItems(spaceId: space.id, query: query),
        );
        for (final item in items) {
          if (item.isFolder) continue;
          hits.add(
            GlobalSearchHit(
              kind: GlobalSearchHitKind.driveItem,
              id: '${item.id}',
              title: item.name,
              subtitle: '微盘 · ${space.name}',
              raw: item,
            ),
          );
          if (hits.length >= size) return hits;
        }
      } catch (_) {}
    }
    return hits;
  }

  Future<void> _runMeetings({
    required int seq,
    required String query,
    required GlobalSearchCategory tab,
    required GlobalSearchEmit emit,
  }) async {
    try {
      final page = await _withTimeout(
        _meetings.fetchListPage(
          keyword: query,
          size: tab == GlobalSearchCategory.meetings ? deepPageSize : 8,
        ),
      );
      final hits = page.items
          .map(
            (m) => GlobalSearchHit(
              kind: GlobalSearchHitKind.meeting,
              id: '${m.meetingId}',
              title: m.title,
              subtitle: m.displayTime,
              raw: m,
            ),
          )
          .toList(growable: false);
      _patch(
        seq,
        GlobalSearchCategory.meetings,
        GlobalSearchGroupState(
          category: GlobalSearchCategory.meetings,
          status: GlobalSearchGroupStatus.ready,
          items: _limit(hits, tab, GlobalSearchCategory.meetings),
          total: page.totalCount > 0 ? page.totalCount : hits.length,
        ),
        emit,
      );
    } catch (e) {
      _fail(seq, GlobalSearchCategory.meetings, e, emit);
    }
  }

  Future<List<XflowProposalItem>> _inbox({required bool force}) async {
    final now = DateTime.now();
    final cached = _inboxItems;
    if (!force &&
        cached != null &&
        _inboxUserId == session.userId &&
        _inboxAt != null &&
        now.difference(_inboxAt!) < inboxTtl) {
      return cached;
    }
    final listCache = ApprovalListCache.instance.peek(
      userId: session.userId,
      listType: 'b1',
    );
    if (!force && listCache != null && listCache.rows.isNotEmpty) {
      _inboxItems = listCache.rows;
      _inboxAt = now;
      _inboxUserId = session.userId;
      return listCache.rows;
    }
    final rows = await _withTimeout(_xflow.fetchMyOpenApprovalInbox());
    _inboxItems = rows;
    _inboxAt = now;
    _inboxUserId = session.userId;
    return rows;
  }

  void _markSkippedWave2(
    int seq,
    GlobalSearchEmit emit, {
    Set<GlobalSearchCategory> except = const {},
  }) {
    for (final c in GlobalSearchCategory.values) {
      if (!c.isWave2 || except.contains(c)) continue;
      final current = _latest.group(c);
      if (current.status == GlobalSearchGroupStatus.ready &&
          current.items.isNotEmpty) {
        continue;
      }
      _patch(
        seq,
        c,
        GlobalSearchGroupState(
          category: c,
          status: GlobalSearchGroupStatus.ready,
          items: current.items,
          total: current.total,
        ),
        emit,
      );
    }
  }

  bool _shouldFetch(GlobalSearchCategory tab, GlobalSearchCategory source) {
    return tab == GlobalSearchCategory.all || tab == source;
  }

  List<GlobalSearchHit> _limit(
    List<GlobalSearchHit> items,
    GlobalSearchCategory tab,
    GlobalSearchCategory source,
  ) {
    final cap = tab == source ? deepPageSize : allPreviewLimit;
    if (items.length <= cap) return items;
    return items.take(cap).toList(growable: false);
  }

  List<NativeConversation> _localConversations() {
    return ConversationInboxCache.instance
            .peek(session.userId)
            ?.conversations ??
        const <NativeConversation>[];
  }

  List<GlobalSearchAppTarget> _appCatalog() {
    final apps = <GlobalSearchAppTarget>[
      const GlobalSearchAppTarget(
        title: '审批',
        subtitle: '待办与已办',
        screenId: 'B1',
      ),
      const GlobalSearchAppTarget(
        title: '发起审批',
        subtitle: '选择模板提交',
        screenId: 'B3',
      ),
      const GlobalSearchAppTarget(
        title: '工作台',
        subtitle: '任务与日常',
        screenId: 'QJA',
      ),
      const GlobalSearchAppTarget(
        title: '知识库',
        subtitle: '文档与问答',
        screenId: 'K1',
      ),
      const GlobalSearchAppTarget(
        title: '企业微盘',
        subtitle: '文件空间',
        screenId: 'FD1',
      ),
      const GlobalSearchAppTarget(
        title: '会议纪要',
        subtitle: 'AI 纪要',
        screenId: 'MM-L',
      ),
      const GlobalSearchAppTarget(
        title: 'Nova',
        subtitle: '智能搜索',
        screenId: 'C4',
      ),
      const GlobalSearchAppTarget(
        title: '通讯录',
        subtitle: '组织与外部联系人',
        screenId: 'C3',
      ),
    ];
    for (final card in XflowService.cachedTemplatesByCategory('biz')) {
      if (!card.enabled || card.templateKey.isEmpty) continue;
      apps.add(
        GlobalSearchAppTarget(
          title: card.title,
          subtitle: card.subtitle.isEmpty ? '发起审批' : card.subtitle,
          templateKey: card.templateKey,
        ),
      );
    }
    return apps;
  }

  GlobalSearchHit _contactHit(NativeContact c) {
    final bits = <String>[
      if ((c.department ?? '').trim().isNotEmpty) c.department!.trim(),
      if ((c.title ?? c.roleLabel ?? '').trim().isNotEmpty)
        (c.title ?? c.roleLabel)!.trim(),
    ];
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.contact,
      id: '${c.userId}',
      title: c.displayLabel,
      subtitle: bits.join(' · '),
      raw: c,
    );
  }

  GlobalSearchHit _conversationHit(NativeConversation c) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.conversation,
      id: '${c.id}',
      title: c.displayTitle,
      subtitle: c.preview,
      time: c.updatedAt,
      raw: c,
    );
  }

  GlobalSearchHit _conversationAsContactHit(NativeConversation c) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.conversation,
      id: '${c.id}',
      title: c.displayTitle,
      subtitle: [
        if ((c.peerDepartment ?? '').trim().isNotEmpty)
          c.peerDepartment!.trim(),
        if ((c.peerRoleLabel ?? '').trim().isNotEmpty) c.peerRoleLabel!.trim(),
      ].join(' · '),
      raw: c,
    );
  }

  List<GlobalSearchHit> _groupMessageHits(List<GlobalMessageHit> rows) {
    final grouped = <int, List<GlobalMessageHit>>{};
    for (final m in rows) {
      if (m.conversationId <= 0) continue;
      grouped.putIfAbsent(m.conversationId, () => <GlobalMessageHit>[]).add(m);
    }
    final hits = <GlobalSearchHit>[];
    for (final entry in grouped.entries) {
      final list = [...entry.value]
        ..sort((a, b) {
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
      var total = list.length;
      for (final m in list) {
        if (m.matchCount > total) total = m.matchCount;
      }
      final real = list.where((m) => m.messageId > 0).toList(growable: false);
      hits.add(
        _threadHit(
          MessageThreadGroup(
            conversationId: entry.key,
            title: list.first.conversationTitle,
            hits: real.isNotEmpty ? real : list,
            totalCount: total,
          ),
        ),
      );
    }
    hits.sort((a, b) {
      final at = a.time?.millisecondsSinceEpoch ?? 0;
      final bt = b.time?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return hits;
  }

  List<GlobalMessageHit> _mergeMessageRows(
    List<GlobalMessageHit> rows,
    List<GlobalSearchHit> seeded,
  ) {
    final out = [...rows];
    final seen = rows.map((m) => m.conversationId).toSet();
    for (final hit in seeded) {
      final raw = hit.raw;
      if (raw is MessageThreadGroup) {
        if (seen.add(raw.conversationId)) out.addAll(raw.hits);
      } else if (raw is GlobalMessageHit) {
        if (seen.add(raw.conversationId)) out.add(raw);
      }
    }
    return out;
  }

  Future<List<GlobalSearchHit>> _enrichThreadCounts(
    List<GlobalSearchHit> hits, {
    required String query,
    required String kind,
  }) async {
    final need = hits.where((h) => h.matchCount <= 1).take(10).toList();
    if (need.isEmpty) return hits;
    final extras = await Future.wait(
      need.map((hit) async {
        final thread = hit.raw;
        if (thread is! MessageThreadGroup || thread.conversationId <= 0) {
          return hit;
        }
        try {
          final page = await _conversations.searchMessagePage(
            conversationId: thread.conversationId,
            query: query,
            size: 40,
          );
          final rows = page.items
              .where(
                (m) =>
                    kind.trim().isEmpty ||
                    m.kind.toUpperCase() == kind.toUpperCase(),
              )
              .map(
                (m) => GlobalMessageHit(
                  conversationId: thread.conversationId,
                  conversationTitle: thread.title,
                  messageId: m.id,
                  senderName: m.senderName,
                  senderUserId: m.senderUserId,
                  senderAvatarPreset: m.senderAvatarPreset,
                  senderAvatarObjectKey: m.senderAvatarObjectKey,
                  bodyText: m.bodyText,
                  kind: m.kind,
                  createdAt: m.createdAt,
                  payload: m.payload,
                ),
              )
              .toList(growable: false);
          if (rows.isEmpty) return hit;
          return _threadHit(
            MessageThreadGroup(
              conversationId: thread.conversationId,
              title: thread.title,
              hits: rows,
              totalCount: page.hasMore ? rows.length + 1 : rows.length,
            ),
          );
        } catch (_) {
          return hit;
        }
      }),
    );
    final byId = {for (final h in extras) h.id: h};
    return [for (final h in hits) byId[h.id] ?? h];
  }

  List<GlobalSearchHit> _previewMessageHits(
    List<NativeConversation> convos,
    String query,
  ) {
    final q = query.toLowerCase();
    final rows = <GlobalMessageHit>[];
    for (final c in convos) {
      if (c.id <= 0) continue;
      if (!c.isPrivate && !c.isGroup && !c.isWorkgroupApproval) continue;
      if (!c.preview.toLowerCase().contains(q)) continue;
      rows.add(_hitFromPreview(c));
    }
    return _groupMessageHits(rows);
  }

  GlobalMessageHit _hitFromPreview(NativeConversation c) {
    final preview = c.preview.trim();
    var sender = '';
    var body = preview;
    final idx = preview.indexOf(':');
    final idxCn = preview.indexOf('：');
    final cut = (idx >= 0 && (idxCn < 0 || idx < idxCn)) ? idx : idxCn;
    if (cut > 0 && cut <= 16) {
      sender = preview.substring(0, cut).trim();
      body = preview.substring(cut + 1).trim();
    }
    return GlobalMessageHit(
      conversationId: c.id,
      conversationTitle: c.displayTitle,
      messageId: 0,
      senderName: sender,
      senderUserId: c.peerUserId ?? 0,
      senderAvatarPreset: c.peerAvatarPreset,
      senderAvatarObjectKey: c.peerAvatarObjectKey,
      senderAvatarUrl: c.peerAvatarUrl,
      bodyText: body,
      kind: 'TEXT',
      createdAt: c.updatedAt,
    );
  }

  bool _hasIdeograph(String q) {
    return q.runes.any(
      (r) =>
          (r >= 0x4E00 && r <= 0x9FFF) ||
          (r >= 0x3400 && r <= 0x4DBF) ||
          (r >= 0xF900 && r <= 0xFAFF),
    );
  }

  GlobalSearchHit _threadHit(MessageThreadGroup thread) {
    final latest = thread.latest;
    final n = thread.count;
    final sender = latest.senderName.trim();
    final body = latest.bodyText.trim();
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.message,
      id: '${thread.conversationId}',
      title: thread.title,
      subtitle: sender.isEmpty ? body : '$sender：$body',
      status: n > 1 ? '$n 条相关' : '',
      time: latest.createdAt,
      raw: thread,
      matchCount: n,
    );
  }

  Future<List<GlobalMessageHit>> loadThreadMessages({
    required int conversationId,
    required String query,
    required String conversationTitle,
    String kind = '',
  }) async {
    final page = await _conversations.searchMessagePage(
      conversationId: conversationId,
      query: query,
      size: 40,
    );
    return page.items
        .where(
          (m) =>
              kind.trim().isEmpty || m.kind.toUpperCase() == kind.toUpperCase(),
        )
        .map(
          (m) => GlobalMessageHit(
            conversationId: conversationId,
            conversationTitle: conversationTitle,
            messageId: m.id,
            senderName: m.senderName,
            senderUserId: m.senderUserId,
            senderAvatarPreset: m.senderAvatarPreset,
            senderAvatarObjectKey: m.senderAvatarObjectKey,
            bodyText: m.bodyText,
            kind: m.kind,
            createdAt: m.createdAt,
            payload: m.payload,
          ),
        )
        .toList(growable: false);
  }

  GlobalSearchHit _approvalHit(XflowProposalItem item) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.approval,
      id: '${item.businessType}:${item.id}',
      title: item.title,
      subtitle: [
        item.status,
        if (item.code.isNotEmpty) item.code,
        if (item.createdByName.isNotEmpty) item.createdByName,
      ].where((e) => e.trim().isNotEmpty).join(' · '),
      status: item.status,
      time: item.createdAt,
      raw: item,
    );
  }

  GlobalSearchHit _intakeHit(dynamic row) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.proposalIntake,
      id: '${row.id}',
      title: '${row.title}',
      subtitle: [
        '协作提案',
        if ('${row.code}'.trim().isNotEmpty) '${row.code}',
        if ('${row.status}'.trim().isNotEmpty) '${row.status}',
      ].join(' · '),
      status: '${row.status}',
      raw: row,
    );
  }

  GlobalSearchHit _taskHit(dynamic task) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.task,
      id: '${task.id}',
      title: '${task.title}',
      subtitle: [
        if ('${task.ownerName}'.trim().isNotEmpty) '${task.ownerName}',
        if ('${task.status}'.trim().isNotEmpty) '${task.status}',
      ].join(' · '),
      status: '${task.status}',
      time: task.dueAt as DateTime?,
      raw: task,
    );
  }

  GlobalSearchHit _kbHit(dynamic doc) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.kbDoc,
      id: '${doc.id}',
      title: '${doc.title}'.trim().isEmpty ? '${doc.fileName}' : '${doc.title}',
      subtitle: '知识库',
      raw: doc,
    );
  }

  GlobalSearchHit _appHit(GlobalSearchAppTarget app) {
    return GlobalSearchHit(
      kind: GlobalSearchHitKind.app,
      id: app.templateKey.isNotEmpty ? app.templateKey : app.screenId,
      title: app.title,
      subtitle: app.subtitle,
      raw: app,
    );
  }

  void _fail(
    int seq,
    GlobalSearchCategory category,
    Object error,
    GlobalSearchEmit emit,
  ) {
    final timeout =
        error is _SearchTimeout ||
        error.toString().contains('TimeoutException');
    _patch(
      seq,
      category,
      GlobalSearchGroupState(
        category: category,
        status: timeout
            ? GlobalSearchGroupStatus.timeout
            : GlobalSearchGroupStatus.error,
        error: timeout ? '超时，点击重试' : '加载失败，点击重试',
      ),
      emit,
    );
  }

  void _patch(
    int seq,
    GlobalSearchCategory category,
    GlobalSearchGroupState group,
    GlobalSearchEmit emit,
  ) {
    if (seq != _seq) return;
    _emit(
      seq,
      _latest.replaceGroup(
        GlobalSearchGroupState(
          category: category,
          status: group.status,
          items: group.items,
          total: group.total,
          error: group.error,
        ),
      ),
      emit,
    );
  }

  void _emit(int seq, GlobalSearchSnapshot snap, GlobalSearchEmit emit) {
    if (seq != _seq) return;
    _latest = snap;
    emit(snap);
  }

  Future<T> _withTimeout<T>(
    Future<T> future, {
    Duration duration = sourceTimeout,
  }) {
    return future.timeout(
      duration,
      onTimeout: () => throw const _SearchTimeout(),
    );
  }
}

class _SearchTimeout implements Exception {
  const _SearchTimeout();
}

extension on GlobalSearchSnapshot {
  GlobalSearchSnapshot copyWithSlowHint(bool value) {
    return GlobalSearchSnapshot(
      seq: seq,
      query: query,
      tab: tab,
      groups: groups,
      slowHint: value,
      queryHint: queryHint,
    );
  }
}
