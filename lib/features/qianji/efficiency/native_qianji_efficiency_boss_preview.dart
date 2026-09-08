import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/dunes_theme.dart';
import '../../../core/widgets/horizontal_drag_scroll_view.dart';
import '../../../core/widgets/spotlight_tour.dart';
import '../../auth/auth_session.dart';
import 'efficiency_models.dart';
import 'efficiency_service.dart';
import 'work_situation_tour.dart';

const _purple = Color(0xFF7651B8);
const _purpleSoft = Color(0xFFF1EAF8);
const _showDeptGlance = false;

enum _Kind { doing, overdue, waiting, meeting, proposal, kb, done, talk }

class _Item {
  const _Item({
    required this.kind,
    required this.title,
    required this.hint,
  });

  final _Kind kind;
  final String title;
  final String hint;

  String get kindLabel => _kindMeta[kind]!.label;
}

class _KindMeta {
  const _KindMeta(this.label, this.color, this.soft);

  final String label;
  final Color color;
  final Color soft;
}

const _kindMeta = {
  _Kind.doing: _KindMeta('进行中', DunesColors.blue, DunesColors.blueSoft),
  _Kind.overdue: _KindMeta('已超期', DunesColors.coral, DunesColors.coralSoft),
  _Kind.waiting: _KindMeta('审批等待中', DunesColors.amber, DunesColors.amberSoft),
  _Kind.meeting: _KindMeta('会议待跟进', Color(0xFF6B5B95), _purpleSoft),
  _Kind.proposal: _KindMeta('提案已退回', DunesColors.pink, Color(0xFFF6E6EC)),
  _Kind.kb: _KindMeta('知识待使用', _purple, _purpleSoft),
  _Kind.done: _KindMeta('本月已完成', DunesColors.green, DunesColors.greenSoft),
  _Kind.talk: _KindMeta('会话抽样', _purple, _purpleSoft),
};

_Kind _parseKind(String raw) {
  switch (raw.trim()) {
    case 'overdue':
      return _Kind.overdue;
    case 'waiting':
      return _Kind.waiting;
    case 'meeting':
      return _Kind.meeting;
    case 'proposal':
      return _Kind.proposal;
    case 'kb':
      return _Kind.kb;
    case 'done':
      return _Kind.done;
    case 'talk':
      return _Kind.talk;
    default:
      return _Kind.doing;
  }
}

List<_Item> _itemsOf(WorkSituationPerson person) {
  if (person.items.isNotEmpty) {
    return [
      for (final item in person.items)
        if (item.title.trim().isNotEmpty)
          _Item(
            kind: _parseKind(item.kind),
            title: item.title.trim(),
            hint: item.hint.trim(),
          ),
    ];
  }
  return [
    if (person.taskOverdue > 0)
      _Item(kind: _Kind.overdue, title: '超期未完成任务', hint: '${person.taskOverdue} 件仍过原定日期'),
    if (person.proposalRejected > 0)
      _Item(kind: _Kind.proposal, title: '被退回的提案', hint: '${person.proposalRejected} 件还没补齐再交'),
    if (person.taskDoing > 0)
      _Item(kind: _Kind.doing, title: '进行中的任务', hint: '${person.taskDoing} 件在办'),
    if (person.taskPending + person.approvalPending > 0)
      _Item(
        kind: _Kind.waiting,
        title: '审批等待中',
        hint: '${person.taskPending + person.approvalPending} 件还在等别人',
      ),
    if (person.meetings > 0 &&
        (person.noActionMeetings > 0 || person.meetingsLinkedTask == 0))
      const _Item(kind: _Kind.meeting, title: '会议待跟进', hint: '纪要或行动项还没变成任务'),
    if (person.kbUnused > 0)
      _Item(kind: _Kind.kb, title: '知识待使用', hint: '${person.kbUnused} 篇上传后未被打开或引用'),
    if (person.taskCompleted > 0)
      _Item(kind: _Kind.done, title: '本月已完成任务', hint: '${person.taskCompleted} 件'),
  ];
}

class _Dept {
  const _Dept({
    required this.id,
    required this.name,
    required this.people,
  });

  final int id;
  final String name;
  final List<WorkSituationPerson> people;
}

enum _SigLevel { weak, mid, good }

class _Sig {
  const _Sig({required this.level, required this.label, required this.why});

  final _SigLevel level;
  final String label;
  final String why;

  bool get isWeak => level == _SigLevel.weak;
  bool get isGood => level == _SigLevel.good;
}

_Sig _taskSig(WorkSituationPerson person) {
  if (person.taskOverdue > 0) {
    return const _Sig(level: _SigLevel.weak, label: '超期未结', why: '有过原定日期还没办完的事');
  }
  if (person.proposalRejected > 0) {
    return const _Sig(level: _SigLevel.weak, label: '被退回', why: '方案被退回，还没补齐再交');
  }
  if (person.taskCompleted > 0 && person.taskOverdue == 0) {
    return const _Sig(level: _SigLevel.good, label: '按期', why: '该办的按期办掉了，没有烂尾');
  }
  if (person.taskDoing > 0 || person.taskPending > 0 || person.approvalPending > 0) {
    return const _Sig(level: _SigLevel.mid, label: '在办', why: '事在推进，还没到点或在等别人');
  }
  return const _Sig(level: _SigLevel.mid, label: '本月少事', why: '这个月任务不多');
}

_Sig _meetSig(WorkSituationPerson person) {
  if (person.meetings > 0 &&
      (person.noActionMeetings > 0 || person.meetingsLinkedTask == 0)) {
    return const _Sig(level: _SigLevel.weak, label: '没落地', why: '会开了，纪要还没变成可跟进的事');
  }
  if (person.meetingsLinkedTask > 0 && person.minutesGenerated > 0) {
    return const _Sig(level: _SigLevel.good, label: '有闭环', why: '会后有纪要或跟进任务');
  }
  return const _Sig(level: _SigLevel.mid, label: '本月少会', why: '这个月开会不多，或会已按期处理');
}

_Sig _kbSig(WorkSituationPerson person) {
  if (person.kbUnused > 0 && person.kbReferences == 0) {
    return const _Sig(level: _SigLevel.weak, label: '没人用', why: '知识传上去了，没被任务或审批用到');
  }
  if (person.kbReferences > 0) {
    return const _Sig(level: _SigLevel.good, label: '用上了', why: '知识进了库，或已经用在工作里');
  }
  return const _Sig(level: _SigLevel.mid, label: '一般', why: '这个月知识库动作不多');
}

_Sig _talkSig(WorkSituationPerson person) {
  final why = person.imTalkWhy.trim();
  switch (person.imTalkLevel) {
    case 'shallow':
      return _Sig(
        level: _SigLevel.weak,
        label: '偏浅',
        why: why.isEmpty ? '抽看会话后，沟通大多停在寒暄或催办。' : why,
      );
    case 'substantial':
      return _Sig(
        level: _SigLevel.good,
        label: '在跟事',
        why: why.isEmpty ? '抽看会话后，沟通在推进具体事情。' : why,
      );
    case 'mixed':
      return _Sig(
        level: _SigLevel.mid,
        label: '有深有浅',
        why: why.isEmpty ? '抽看会话后，有的在跟事，有的偏水。' : why,
      );
    case 'quiet':
      return const _Sig(level: _SigLevel.mid, label: '本月少聊', why: '这个月几乎没有可分析的会话');
    default:
      if (person.imSessions <= 0) {
        return const _Sig(level: _SigLevel.mid, label: '本月少聊', why: '这个月几乎没有可分析的会话');
      }
      return const _Sig(
        level: _SigLevel.mid,
        label: '待看会话',
        why: '点开后会抽会话让 AI 判断是否在推进事情，不看有没有发业务卡片。',
      );
  }
}

String _talkDetailText(WorkSituationPerson person) {
  final why = person.imTalkWhy.trim();
  if (why.isNotEmpty) {
    return why;
  }
  switch (person.imTalkLevel) {
    case 'quiet':
      return '这个月几乎没有可分析的会话。';
    case 'shallow':
      return '抽看会话后，沟通大多停在寒暄或催办。';
    case 'substantial':
      return '抽看会话后，沟通在推进具体事情。';
    case 'mixed':
      return '抽看会话后，有的在跟事，有的偏水。';
    default:
      if (person.imSessions <= 0) {
        return '这个月几乎没有可分析的会话。';
      }
      return '抽本月会话给 AI 看是否在推进事情。分析完成后会写出判断，界面不展示聊天原文。';
  }
}

bool _hasWeak(WorkSituationPerson person) =>
    _taskSig(person).isWeak ||
    _meetSig(person).isWeak ||
    _kbSig(person).isWeak ||
    _talkSig(person).isWeak;

class _EffRoll {
  const _EffRoll({
    required this.task,
    required this.meet,
    required this.kb,
    required this.talk,
    required this.n,
  });

  final int task;
  final int meet;
  final int kb;
  final int talk;
  final int n;
}

_EffRoll _effRoll(Iterable<WorkSituationPerson> people) {
  var task = 0;
  var meet = 0;
  var kb = 0;
  var talk = 0;
  var n = 0;
  for (final person in people) {
    n++;
    if (_taskSig(person).isGood) task++;
    if (_meetSig(person).isGood) meet++;
    if (_kbSig(person).isGood) kb++;
    if (_talkSig(person).isGood) talk++;
  }
  return _EffRoll(task: task, meet: meet, kb: kb, talk: talk, n: n == 0 ? 1 : n);
}

String _deptSay(_Dept dept) {
  final weakTask = dept.people.where((p) => _taskSig(p).isWeak).length;
  final weakMeet = dept.people.where((p) => _meetSig(p).isWeak).length;
  final weakKb = dept.people.where((p) => _kbSig(p).isWeak).length;
  final weakTalk = dept.people.where((p) => _talkSig(p).isWeak).length;
  if (weakTask > 0) return '$weakTask人事没办完';
  if (weakMeet > 0) return '$weakMeet人开会没落地';
  if (weakKb > 0) return '$weakKb人知识没人用';
  if (weakTalk > 0) return '$weakTalk人沟通偏浅';
  return '比较扎实';
}

String _monthLabel(DateTime month) => '${month.year}年${month.month}月';

String _monthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

class NativeQianjiEfficiencyBossPreview extends StatefulWidget {
  const NativeQianjiEfficiencyBossPreview({
    super.key,
    required this.onBack,
    this.session,
    this.service,
    this.now,
    this.viewAll = true,
    this.viewerName = '',
  });

  final VoidCallback onBack;
  final AuthSession? session;
  final EfficiencyService? service;
  final DateTime? now;
  final bool viewAll;
  final String viewerName;

  @override
  State<NativeQianjiEfficiencyBossPreview> createState() =>
      _NativeQianjiEfficiencyBossPreviewState();
}

class _NativeQianjiEfficiencyBossPreviewState
    extends State<NativeQianjiEfficiencyBossPreview> {
  late DateTime _month;
  late final EfficiencyService? _service;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _filter = 'all';
  String _query = '';
  int? _departmentId;
  WorkSituationPerson? _person;
  WorkSituationBoard? _board;
  bool _loading = true;
  String? _error;
  int _generation = 0;
  final Set<int> _open = {};
  final _helpKey = GlobalKey();
  final _monthBarKey = GlobalKey();
  final _deptBarKey = GlobalKey();
  final _filterBarKey = GlobalKey();
  late final WorkSituationTourPrefs _tourPrefs;
  bool _tourAutoChecked = false;
  bool _tourOpen = false;
  int _tourSeq = 0;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _month = DateTime(now.year, now.month - 1);
    _service = widget.service ??
        (widget.session == null
            ? null
            : EfficiencyService(session: widget.session!));
    _tourPrefs = WorkSituationTourPrefs(widget.session?.userId ?? 0);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _monthId => _monthKey(_month);

  List<DateTime> get _recentMonths {
    final now = widget.now ?? DateTime.now();
    return [
      for (var i = 0; i < 6; i++) DateTime(now.year, now.month - i),
    ];
  }

  List<_Dept> get _depts {
    final people = _board?.people ?? const <WorkSituationPerson>[];
    final depts = _board?.departments ?? const <WorkSituationDept>[];
    if (depts.isEmpty) {
      final grouped = <int, List<WorkSituationPerson>>{};
      for (final person in people) {
        grouped.putIfAbsent(person.departmentId, () => []).add(person);
      }
      return [
        for (final entry in grouped.entries)
          _Dept(
            id: entry.key,
            name: entry.value.first.departmentName.isEmpty
                ? '未分配部门'
                : entry.value.first.departmentName,
            people: entry.value,
          ),
      ];
    }
    return [
      for (final dept in depts)
        _Dept(
          id: dept.id,
          name: dept.name,
          people: [
            for (final person in people)
              if (person.departmentId == dept.id) person,
          ],
        ),
    ];
  }

  List<_Dept> get _scopedDepts {
    if (_departmentId == null) return _depts;
    return [for (final dept in _depts) if (dept.id == _departmentId) dept];
  }

  List<WorkSituationPerson> get _allPeople =>
      [for (final dept in _scopedDepts) ...dept.people];

  bool _matchPerson(WorkSituationPerson person) {
    final q = _query.trim();
    if (q.isEmpty) return true;
    return person.name.contains(q) ||
        person.title.contains(q) ||
        person.departmentName.contains(q) ||
        person.note.contains(q);
  }

  bool _passFilter(WorkSituationPerson person) {
    if (_filter == 'task') return _taskSig(person).isWeak;
    if (_filter == 'meet') return _meetSig(person).isWeak;
    if (_filter == 'kb') return _kbSig(person).isWeak;
    if (_filter == 'talk') return _talkSig(person).isWeak;
    return true;
  }

  List<_Dept> get _visibleDepts {
    final q = _query.trim();
    final out = <_Dept>[];
    for (final dept in _scopedDepts) {
      final nameHit = q.isNotEmpty && dept.name.contains(q);
      final people = dept.people.where((person) {
        if (q.isNotEmpty && !nameHit && !_matchPerson(person)) return false;
        return _passFilter(person);
      }).toList();
      if (people.isNotEmpty || nameHit) {
        out.add(_Dept(id: dept.id, name: dept.name, people: people));
      }
    }
    return out;
  }

  Future<void> _load() async {
    final service = _service;
    if (service == null) {
      setState(() {
        _loading = false;
        _error = '未登录，无法加载工作情况';
      });
      unawaited(_maybeStartTour());
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await service.fetchWorkSituation(month: _monthId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _board = board;
        _loading = false;
        if (_departmentId != null &&
            board.departments.every((d) => d.id != _departmentId)) {
          _departmentId = null;
        }
        if (_open.isEmpty) {
          _open.addAll(
            board.departments.isNotEmpty
                ? board.departments.map((d) => d.id)
                : board.people.map((p) => p.departmentId),
          );
        }
      });
      unawaited(_maybeStartTour());
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '').trim();
      });
      unawaited(_maybeStartTour());
    }
  }

  Future<void> _openPerson(WorkSituationPerson person) async {
    setState(() => _person = person);
    final service = _service;
    if (service == null || person.userId <= 0) return;
    try {
      final detail = await service.fetchWorkSituationPerson(
        month: _monthId,
        userId: person.userId,
      );
      if (!mounted || _person?.userId != person.userId) return;
      setState(() => _person = detail);
    } catch (_) {}
  }

  Future<void> _pickMonth() async {
    final now = widget.now ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month + 1, 0),
      helpText: '选择月份',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _month = DateTime(picked.year, picked.month);
      _person = null;
    });
    await _load();
  }

  Future<void> _maybeStartTour() async {
    if (_tourAutoChecked || _person != null) return;
    _tourAutoChecked = true;
    try {
      if (await _tourPrefs.hasSeen()) return;
    } catch (_) {
      return;
    }
    if (!mounted || _person != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tourOpen || _person != null) return;
      setState(() => _tourOpen = true);
    });
  }

  void _openTour() {
    setState(() {
      _person = null;
      _tourSeq += 1;
      _tourOpen = true;
    });
  }

  Future<void> _closeTour() async {
    if (_tourOpen) setState(() => _tourOpen = false);
    try {
      await _tourPrefs.markSeen();
    } catch (_) {}
  }

  List<SpotlightTourStep> get _tourSteps => [
    SpotlightTourStep(
      targetKey: _monthBarKey,
      title: '先选月份',
      body: '工作情况按自然月汇总。切月份后，下面的人和问题标签都会跟着变。',
    ),
    SpotlightTourStep(
      targetKey: _deptBarKey,
      title: '按部门看',
      body: '可以看全部部门，或只看某一个部门。没开通「查看全部」时，只能看自己和直接下级。',
    ),
    SpotlightTourStep(
      targetKey: _filterBarKey,
      title: '四个问题标签',
      body:
          '任务没办完、开会没落地、知识没用上、沟通偏浅。任务、会议、知识按单据统计；沟通是抽本月会话给 AI 看有没有把事情推进去，不打分。点标签只看对应的人。',
    ),
    SpotlightTourStep(
      targetKey: _helpKey,
      title: '随时看口径',
      body: '右上角问号可以再看每项是怎么算的。第一次看完后不会再自动出现，点问号里的「再看一遍指引」就能重来。',
      holeRadius: 22,
    ),
  ];

  void _showGuide({bool offerTour = true}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8E2EE),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '这些内容根据什么分析',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '按你选的自然月，汇总本人权限范围内的任务、审批/提案、会议纪要、知识库，并抽看 IM 会话。沟通由 AI 判断是否在推进事情，不打分。界面不展示聊天原文。',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  const _GuideItem(
                    title: '任务没办完',
                    body:
                        '来自任务助手：当月有过原定日期仍未完成的任务，或提案被退回还没补齐再交。筛选后只看这类人。',
                  ),
                  const _GuideItem(
                    title: '开会没落地',
                    body:
                        '来自会议纪要：这个月开过会，但纪要没有行动项，或行动项还没变成可跟进任务。不听录音、不读转写全文。',
                  ),
                  const _GuideItem(
                    title: '知识没用上',
                    body: '来自知识库：这个月上传了文档，但没被打开，也没有被任务或审批引用。',
                  ),
                  const _GuideItem(
                    title: '沟通偏浅',
                    body:
                        '抽本月活跃会话给 AI 看有没有把事情说到结论或下一步。寒暄、收到、反复催会标成偏浅；对齐目标和推进事项算在跟事。不看有没有发业务卡片，界面不展示聊天原文。点开人后会分析，凌晨也会批量看一遍。',
                  ),
                  if (offerTour) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openTour();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                          side: const BorderSide(color: Color(0xFFD9CDEA)),
                        ),
                        child: const Text('再看一遍指引'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _goHome() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _person = null);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 80;
    final monthLabel = _monthLabel(_month);
    final scopeLabel = _board?.scopeLabel.isNotEmpty == true
        ? _board!.scopeLabel
        : (widget.viewAll ? '全部部门' : '本人及下级');
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5FA),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(
                    onBack: _person != null ? _goHome : widget.onBack,
                    title: _person != null ? _person!.name : '工作情况',
                    subtitle: _person != null
                        ? '${_person!.title} · $monthLabel'
                        : monthLabel,
                    helpKey: _helpKey,
                    onHelp: _showGuide,
                  ),
                  if (_person == null)
                    _PinnedFilters(
                      compact: keyboardOpen,
                      month: _month,
                      months: _recentMonths,
                      monthLabel: monthLabel,
                      scopeLabel: scopeLabel,
                      search: _search,
                      searchFocus: _searchFocus,
                      filter: _filter,
                      departmentId: _departmentId,
                      departments: _depts,
                      monthKey: _monthBarKey,
                      deptKey: _deptBarKey,
                      filterKey: _filterBarKey,
                      onMonth: (value) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() {
                          _month = value;
                          _person = null;
                        });
                        unawaited(_load());
                      },
                      onPickMonth: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        unawaited(_pickMonth());
                      },
                      onQuery: (value) => setState(() {
                        _query = value;
                        if (value.trim().isNotEmpty) {
                          _open.addAll(_visibleDepts.map((d) => d.id));
                        }
                      }),
                      onFilter: (value) => setState(() => _filter = value),
                      onDepartment: (id) => setState(() {
                        _departmentId = id;
                        if (id != null) _open.add(id);
                      }),
                    ),
                  Expanded(
                    child: _person != null
                        ? _PersonDetail(
                            person: _person!,
                            monthLabel: monthLabel,
                            onOpenDept: () {
                              setState(() {
                                _departmentId = _person!.departmentId;
                                _person = null;
                              });
                            },
                          )
                        : _Board(
                            loading: _loading,
                            error: _error,
                            compact: keyboardOpen,
                            monthLabel: monthLabel,
                            scopeLabel: scopeLabel,
                            query: _query,
                            open: _open,
                            depts: _visibleDepts,
                            sourceDepts: _scopedDepts,
                            onRetry: _load,
                            onToggle: (id) => setState(() {
                              if (_open.contains(id)) {
                                _open.remove(id);
                              } else {
                                _open.add(id);
                              }
                            }),
                            onPerson: _openPerson,
                            onDept: (id) => setState(() => _departmentId = id),
                          ),
                  ),
                ],
              ),
              if (_tourOpen)
                Positioned.fill(
                  child: SpotlightTourOverlay(
                    key: ValueKey(_tourSeq),
                    steps: _tourSteps,
                    onClose: _closeTour,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.title,
    required this.onHelp,
    this.subtitle,
    this.helpKey,
  });

  final VoidCallback onBack;
  final VoidCallback onHelp;
  final String title;
  final String? subtitle;
  final Key? helpKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E2EE))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 11, color: DunesColors.text3),
                  ),
              ],
            ),
          ),
          IconButton(
            key: helpKey,
            tooltip: '这些内容怎么分析',
            onPressed: onHelp,
            icon: const Icon(Icons.help_outline_rounded, color: _purple),
          ),
        ],
      ),
    );
  }
}

class _PinnedFilters extends StatelessWidget {
  const _PinnedFilters({
    required this.compact,
    required this.month,
    required this.months,
    required this.monthLabel,
    required this.scopeLabel,
    required this.search,
    required this.searchFocus,
    required this.filter,
    required this.departmentId,
    required this.departments,
    required this.onMonth,
    required this.onPickMonth,
    required this.onQuery,
    required this.onFilter,
    required this.onDepartment,
    this.monthKey,
    this.deptKey,
    this.filterKey,
  });

  final bool compact;
  final DateTime month;
  final List<DateTime> months;
  final String monthLabel;
  final String scopeLabel;
  final TextEditingController search;
  final FocusNode searchFocus;
  final String filter;
  final int? departmentId;
  final List<_Dept> departments;
  final ValueChanged<DateTime> onMonth;
  final VoidCallback onPickMonth;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;
  final ValueChanged<int?> onDepartment;
  final Key? monthKey;
  final Key? deptKey;
  final Key? filterKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F5FA),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ...[
              KeyedSubtree(
                key: monthKey,
                child: _MonthBar(
                  month: month,
                  months: months,
                  onChanged: onMonth,
                  onPick: onPickMonth,
                ),
              ),
              const SizedBox(height: 10),
              KeyedSubtree(
                key: deptKey,
                child: _DeptBar(
                  selectedId: departmentId,
                  departments: departments,
                  onChanged: onDepartment,
                ),
              ),
              const SizedBox(height: 10),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$monthLabel · ${departmentId == null ? scopeLabel : departments.where((d) => d.id == departmentId).map((d) => d.name).join()}',
                  style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                ),
              ),
            _SearchField(
              controller: search,
              focusNode: searchFocus,
              onChanged: onQuery,
            ),
            if (!compact) ...[
              const SizedBox(height: 10),
              KeyedSubtree(
                key: filterKey,
                child: _FilterBar(filter: filter, onChanged: onFilter),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.loading,
    required this.error,
    required this.compact,
    required this.monthLabel,
    required this.scopeLabel,
    required this.query,
    required this.open,
    required this.depts,
    required this.sourceDepts,
    required this.onRetry,
    required this.onToggle,
    required this.onPerson,
    required this.onDept,
  });

  final bool loading;
  final String? error;
  final bool compact;
  final String monthLabel;
  final String scopeLabel;
  final String query;
  final Set<int> open;
  final List<_Dept> depts;
  final List<_Dept> sourceDepts;
  final Future<void> Function() onRetry;
  final ValueChanged<int> onToggle;
  final ValueChanged<WorkSituationPerson> onPerson;
  final ValueChanged<int> onDept;

  @override
  Widget build(BuildContext context) {
    if (loading && sourceDepts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && sourceDepts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
        children: [
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: DunesColors.text2)),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: onRetry, child: const Text('重试')),
          ),
        ],
      );
    }
    final searching = query.trim().isNotEmpty;
    final hitPeople = depts.fold<int>(0, (sum, dept) => sum + dept.people.length);
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
        children: [
          if (!compact && !searching) ...[
            _HeroCard(monthLabel: monthLabel, scopeLabel: scopeLabel),
            const SizedBox(height: 12),
            _GlanceCard(people: [for (final d in sourceDepts) ...d.people]),
            const SizedBox(height: 12),
            if (_showDeptGlance) ...[
              _DeptGlanceList(depts: sourceDepts, onOpen: onDept),
              const SizedBox(height: 12),
            ],
          ] else if (searching) ...[
            Text(
              '找到 $hitPeople 人',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
          ],
          if (depts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '这个范围暂时没有可看的人',
                textAlign: TextAlign.center,
                style: TextStyle(color: DunesColors.text3),
              ),
            )
          else
            for (final dept in depts) ...[
              _DeptCard(
                dept: dept,
                expanded: searching || open.contains(dept.id),
                onToggle: () => onToggle(dept.id),
                onPerson: onPerson,
                onSelect: () => onDept(dept.id),
              ),
              const SizedBox(height: 10),
            ],
          const Text(
            '按任务、会议、知识和会话抽样看，沟通由 AI 判断，不打分。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.monthLabel, required this.scopeLabel});

  final String monthLabel;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF5F3E82), Color(0xFF8965B5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$monthLabel · $scopeLabel', style: const TextStyle(color: Color(0xDFFFFFFF), fontSize: 13)),
          const SizedBox(height: 6),
          const Text(
            '每个人工作实不实',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.months,
    required this.onChanged,
    required this.onPick,
  });

  final DateTime month;
  final List<DateTime> months;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return HorizontalDragScrollView(
      child: Row(
        children: [
          for (final item in months) ...[
            _Chip(
              label: '${item.month}月',
              selected: item.year == month.year && item.month == month.month,
              onTap: () => onChanged(item),
            ),
            const SizedBox(width: 8),
          ],
          _Chip(
            label: '更多',
            selected: !months.any((item) => item.year == month.year && item.month == month.month),
            onTap: onPick,
          ),
        ],
      ),
    );
  }
}

class _DeptBar extends StatelessWidget {
  const _DeptBar({
    required this.selectedId,
    required this.departments,
    required this.onChanged,
  });

  final int? selectedId;
  final List<_Dept> departments;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return HorizontalDragScrollView(
      child: Row(
        children: [
          _Chip(
            label: '全部部门',
            selected: selectedId == null,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 8),
          for (final dept in departments) ...[
            _Chip(
              label: '${dept.name} ${dept.people.length}',
              selected: selectedId == dept.id,
              onTap: () => onChanged(dept.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _purple : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? _purple : const Color(0xFFE9E3EE)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : DunesColors.text2,
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      onTapOutside: (_) => focusNode.unfocus(),
      onSubmitted: (_) => focusNode.unfocus(),
      decoration: InputDecoration(
        hintText: '搜人、部门',
        hintStyle: const TextStyle(fontSize: 13, color: DunesColors.text3),
        prefixIcon: const Icon(Icons.search_rounded, color: DunesColors.text3),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                  focusNode.unfocus();
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE9E3EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE9E3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _purple),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onChanged});

  final String filter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String id, String label) {
      return _Chip(label: label, selected: filter == id, onTap: () => onChanged(id));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('all', '全部'),
        chip('task', '任务没办完'),
        chip('meet', '开会没落地'),
        chip('kb', '知识没用上'),
        chip('talk', '沟通偏浅'),
      ],
    );
  }
}

class _EffMeter extends StatelessWidget {
  const _EffMeter({required this.good, required this.n});

  final int good;
  final int n;

  @override
  Widget build(BuildContext context) {
    final pct = n <= 0 ? 0.0 : good / n;
    final color = pct >= 0.6
        ? DunesColors.green
        : pct >= 0.35
            ? DunesColors.amber
            : DunesColors.coral;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 22,
        width: double.infinity,
        child: ColoredBox(
          color: const Color(0xFFF3EEF6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: ColoredBox(color: color, child: const SizedBox.expand()),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlanceCard extends StatelessWidget {
  const _GlanceCard({required this.people});

  final List<WorkSituationPerson> people;

  @override
  Widget build(BuildContext context) {
    final e = _effRoll(people);
    Widget row(String label, int good, String unit) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Text(
                  '$good/${e.n} $unit',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _EffMeter(good: good, n: e.n),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('工作实不实', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            '看任务办没办完、开会有没有下文、知识有没有人用、会话里是不是在跟具体事。沟通抽会话给 AI 看，不打分。',
            style: TextStyle(fontSize: 12, color: DunesColors.text3, height: 1.4),
          ),
          const SizedBox(height: 12),
          row('把事办掉', e.task, '按期'),
          row('好好开会', e.meet, '有闭环'),
          row('用好知识库', e.kb, '用上了'),
          row('沟通跟得上事', e.talk, '在跟事'),
        ],
      ),
    );
  }
}

class _DeptGlanceList extends StatelessWidget {
  const _DeptGlanceList({required this.depts, required this.onOpen});

  final List<_Dept> depts;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${depts.length}个部门',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          for (final dept in depts)
            InkWell(
              onTap: () => onOpen(dept.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(dept.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const Spacer(),
                        Text(
                          '${dept.people.length}人 · ${_deptSay(dept)}',
                          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (_) {
                        final e = _effRoll(dept.people);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '任务 ${e.task}/${e.n} · 开会 ${e.meet}/${e.n} · 知识 ${e.kb}/${e.n} · 沟通 ${e.talk}/${e.n}',
                              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                            ),
                            const SizedBox(height: 8),
                            _EffMeter(good: e.task + e.meet + e.kb + e.talk, n: e.n * 4),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeptCard extends StatelessWidget {
  const _DeptCard({
    required this.dept,
    required this.expanded,
    required this.onToggle,
    required this.onPerson,
    required this.onSelect,
  });

  final _Dept dept;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<WorkSituationPerson> onPerson;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E3EE)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            onLongPress: onSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onSelect,
                      child: Text(
                        '${dept.name} · ${dept.people.length}人',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final person in dept.people)
              _PersonRow(person: person, onTap: () => onPerson(person)),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});

  final WorkSituationPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(name: person.name, alert: _hasWeak(person)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(person.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          person.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: DunesColors.text3),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _SigPills(person: person),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SigPills extends StatelessWidget {
  const _SigPills({required this.person});

  final WorkSituationPerson person;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_taskSig(person), '任务'),
      (_meetSig(person), '开会'),
      (_kbSig(person), '知识'),
      (_talkSig(person), '沟通'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in items) _sigChip(item.$1, item.$2),
      ],
    );
  }

  Widget _sigChip(_Sig sig, String name) {
    final Color bg;
    final Color fg;
    switch (sig.level) {
      case _SigLevel.good:
        bg = DunesColors.greenSoft;
        fg = DunesColors.green;
      case _SigLevel.mid:
        bg = const Color(0xFFF4E8D2);
        fg = DunesColors.amber;
      case _SigLevel.weak:
        bg = DunesColors.coralSoft;
        fg = DunesColors.coral;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        '$name${sig.label}',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _WhyLines extends StatelessWidget {
  const _WhyLines({required this.person});

  final WorkSituationPerson person;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('任务', _taskSig(person)),
      ('开会', _meetSig(person)),
      ('知识', _kbSig(person)),
      ('沟通', _talkSig(person)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) ...[
          const SizedBox(height: 10),
          Text('${row.$1}${row.$2.label}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(row.$2.why, style: const TextStyle(fontSize: 13, height: 1.45, color: DunesColors.text2)),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.alert});

  final String name;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final label = name.isEmpty ? '?' : name.substring(0, 1);
    return CircleAvatar(
      radius: 16,
      backgroundColor: alert ? DunesColors.coralSoft : DunesColors.blueSoft,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: alert ? DunesColors.coral : DunesColors.blue,
        ),
      ),
    );
  }
}

class _PersonDetail extends StatelessWidget {
  const _PersonDetail({
    required this.person,
    required this.monthLabel,
    required this.onOpenDept,
  });

  final WorkSituationPerson person;
  final String monthLabel;
  final VoidCallback onOpenDept;

  @override
  Widget build(BuildContext context) {
    final items = _itemsOf(person);
    final taskItems = items
        .where((i) =>
            i.kind == _Kind.doing ||
            i.kind == _Kind.overdue ||
            i.kind == _Kind.waiting ||
            i.kind == _Kind.proposal ||
            i.kind == _Kind.done)
        .toList();
    final meetItems = items.where((i) => i.kind == _Kind.meeting).toList();
    final kbItems = items.where((i) => i.kind == _Kind.kb).toList();
    final talkItems = items.where((i) => i.kind == _Kind.talk).toList();
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE9E3EE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: person.name, alert: _hasWeak(person)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                        Text(
                          '${person.departmentName} · ${person.title} · $monthLabel',
                          style: const TextStyle(color: DunesColors.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SigPills(person: person),
              _WhyLines(person: person),
              if (person.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(person.note, style: const TextStyle(height: 1.5, fontSize: 14)),
              ],
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onOpenDept,
                child: Text(
                  '看${person.departmentName}',
                  style: const TextStyle(color: _purple, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (taskItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DetailSection(title: '任务怎么看', items: taskItems),
        ],
        if (meetItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DetailSection(title: '开会怎么看', items: meetItems),
        ],
        if (kbItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DetailSection(title: '知识怎么看', items: kbItems),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE9E3EE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('沟通怎么看', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                _talkDetailText(person),
                style: const TextStyle(fontSize: 13, height: 1.45, color: DunesColors.text2),
              ),
              if (talkItems.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final item in talkItems) _ItemTile(item: item),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          for (final item in items) _ItemTile(item: item),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta[item.kind]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: meta.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              meta.label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: meta.color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (item.hint.isNotEmpty)
                  Text(item.hint, style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: DunesColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}
