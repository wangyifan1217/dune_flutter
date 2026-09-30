import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'task_avatar.dart';
import 'task_api.dart';
import 'task_models.dart';

Future<List<TaskAssignee>?> showTaskHelperPicker(
  BuildContext context, {
  required TaskApi api,
  required Set<int> selectedIds,
  required int excludeUserId,
  List<TaskAssignee> known = const [],
  String title = '选择协助人',
  bool single = false,
  String? scope,
}) {
  return showModalBottomSheet<List<TaskAssignee>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _TaskHelperPicker(
      api: api,
      selectedIds: selectedIds,
      known: known,
      excludeUserId: excludeUserId,
      title: title,
      single: single,
      scope: scope,
    ),
  );
}

Future<TaskAssignee?> showTaskColleaguePicker(
  BuildContext context, {
  required TaskApi api,
  required int excludeUserId,
  String title = '选择同事',
}) async {
  final picked = await showTaskHelperPicker(
    context,
    api: api,
    selectedIds: const {},
    excludeUserId: excludeUserId,
    title: title,
    single: true,
  );
  if (picked == null || picked.isEmpty) return null;
  return picked.first;
}

class _TaskHelperPicker extends StatefulWidget {
  const _TaskHelperPicker({
    required this.api,
    required this.selectedIds,
    required this.known,
    required this.excludeUserId,
    required this.title,
    required this.single,
    this.scope,
  });

  final TaskApi api;
  final Set<int> selectedIds;
  final List<TaskAssignee> known;
  final int excludeUserId;
  final String title;
  final bool single;
  final String? scope;

  @override
  State<_TaskHelperPicker> createState() => _TaskHelperPickerState();
}

class _TaskHelperPickerState extends State<_TaskHelperPicker> {
  final _searchCtrl = TextEditingController();
  final _selected = <int>{};
  final _byId = <int, TaskAssignee>{};
  List<TaskAssignee> _people = const [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.selectedIds);
    for (final person in widget.known) {
      if (person.id > 0) _byId[person.id] = person;
    }
    unawaited(_load(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = widget.scope == null
          ? await widget.api.searchColleagues(q)
          : await widget.api.listAssignees(q: q, scope: widget.scope);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        for (final person in list) {
          _byId[person.id] = person;
        }
        _people = list.where((e) => e.id != widget.excludeUserId).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_load(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.62;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: '输入姓名筛选',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: _onSearch,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: DunesColors.text3),
                      ),
                    )
                  : _people.isEmpty
                  ? const Center(
                      child: Text(
                        '没有匹配的同事',
                        style: TextStyle(color: DunesColors.text3),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _people.length,
                      itemBuilder: (_, i) {
                        final person = _people[i];
                        final selected = _selected.contains(person.id);
                        return ListTile(
                          leading: buildTaskUserAvatar(
                            session: widget.api.session,
                            name: person.displayName,
                            userId: person.id,
                            avatarPreset: person.avatarPreset,
                            avatarObjectKey: person.avatarObjectKey,
                            avatarUrl: person.avatarUrl,
                            size: 38,
                          ),
                          title: Text(person.displayName),
                          subtitle: person.departmentName.isEmpty
                              ? null
                              : Text(person.departmentName),
                          trailing: widget.single
                              ? null
                              : Checkbox(
                                  value: selected,
                                  onChanged: (checked) =>
                                      _toggle(person, checked),
                                ),
                          onTap: () {
                            if (widget.single) {
                              Navigator.pop(context, [person]);
                            } else {
                              _toggle(person, !selected);
                            }
                          },
                        );
                      },
                    ),
            ),
            if (!widget.single)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.pop(context, [
                            for (final id in _selected)
                              if (_byId[id] != null &&
                                  id != widget.excludeUserId)
                                _byId[id]!,
                          ]);
                        },
                  child: Text('确定（${_selected.length}）'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggle(TaskAssignee person, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(person.id);
      } else {
        _selected.remove(person.id);
      }
    });
  }
}
