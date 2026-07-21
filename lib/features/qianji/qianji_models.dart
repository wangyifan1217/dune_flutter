import 'package:flutter/material.dart';

enum QianjiEntityKind { platform, product, capability }

enum QianjiEntityStatus { developing, online }

enum QianjiGanttState { done, active, pending }

class QianjiEntity {
  const QianjiEntity({
    required this.id,
    required this.name,
    required this.kind,
    required this.tag,
    required this.status,
    required this.owner,
    required this.industryOrMode,
    required this.statusLabel,
    required this.application,
    this.relatedProducts,
  });

  final String id;
  final String name;
  final QianjiEntityKind kind;
  final int tag;
  final QianjiEntityStatus status;
  final String owner;
  final String industryOrMode;
  final String statusLabel;
  final String application;
  final String? relatedProducts;

  String get kindLabel => switch (kind) {
        QianjiEntityKind.platform => '平台',
        QianjiEntityKind.product => '产品',
        QianjiEntityKind.capability => '能力',
      };

  IconData get kindIcon => switch (kind) {
        QianjiEntityKind.platform => Icons.hub_outlined,
        QianjiEntityKind.product => Icons.inventory_2_outlined,
        QianjiEntityKind.capability => Icons.auto_awesome_outlined,
      };
}

class QianjiTagStats {
  const QianjiTagStats({
    required this.total,
    required this.dev,
    required this.online,
  });

  final int total;
  final int dev;
  final int online;
}

class QianjiCapabilityLink {
  const QianjiCapabilityLink({
    required this.title,
    required this.description,
    required this.status,
    required this.icon,
  });

  final String title;
  final String description;
  final String status;
  final IconData icon;
}

class QianjiRequirement {
  const QianjiRequirement({
    required this.code,
    required this.name,
    this.kind = '迭代需求',
    this.phase = '',
  });

  final String code;
  final String name;
  final String kind;
  final String phase;
}

class QianjiDevFile {
  const QianjiDevFile({
    required this.name,
    required this.size,
    required this.icon,
    this.meta = '',
  });

  final String name;
  final String size;
  final IconData icon;
  final String meta;
}

class QianjiGanttBar {
  const QianjiGanttBar({
    required this.name,
    required this.left,
    required this.width,
    required this.state,
  });

  final String name;
  final double left;
  final double width;
  final QianjiGanttState state;
}

class QianjiPhase {
  const QianjiPhase({required this.name, required this.state});

  final String name;
  final QianjiGanttState state;
}

class QianjiPersonChange {
  const QianjiPersonChange({
    required this.role,
    required this.from,
    required this.to,
    required this.time,
  });

  final String role;
  final String from;
  final String to;
  final String time;
}

class QianjiIteration {
  const QianjiIteration({
    required this.id,
    required this.version,
    required this.statusLabel,
    required this.active,
    required this.phase,
    required this.meta,
    required this.owner,
    required this.members,
    required this.description,
    required this.ganttScale,
    required this.ganttBars,
    required this.phases,
    required this.currentLabel,
    required this.requirements,
    required this.files,
    this.personChanges = const [],
    this.nowPercent,
  });

  final String id;
  final String version;
  final String statusLabel;
  final bool active;
  final String phase;
  final String meta;
  final String owner;
  final String members;
  final String description;
  final List<String> ganttScale;
  final List<QianjiGanttBar> ganttBars;
  final List<QianjiPhase> phases;
  final String currentLabel;
  final List<QianjiRequirement> requirements;
  final List<QianjiDevFile> files;
  final List<QianjiPersonChange> personChanges;
  final double? nowPercent;
}

class QianjiProductDetail {
  const QianjiProductDetail({
    required this.entity,
    required this.description,
    required this.demoLabel,
    required this.statusLabel,
    required this.capabilities,
    required this.iterations,
  });

  final QianjiEntity entity;
  final String description;
  final String demoLabel;
  final String statusLabel;
  final List<QianjiCapabilityLink> capabilities;
  final List<QianjiIteration> iterations;

  String get name => entity.name;
  String get owner => entity.owner;
  String get industryOrMode => entity.industryOrMode;
  String get application => entity.application;
}

/// 原型静态样例数据（对齐 qianji-app.html Hub / Detail / Iteration）。
abstract final class QianjiStaticCatalog {
  static const Map<int, QianjiTagStats> stats = {
    1: QianjiTagStats(total: 3, dev: 1, online: 2),
    2: QianjiTagStats(total: 2, dev: 1, online: 1),
    3: QianjiTagStats(total: 2, dev: 1, online: 1),
  };

  static const List<QianjiEntity> entities = [
    QianjiEntity(
      id: 'qj-platform',
      name: '千机平台',
      kind: QianjiEntityKind.platform,
      tag: 1,
      status: QianjiEntityStatus.developing,
      owner: '杨静',
      industryOrMode: '全行业',
      statusLabel: '研发中',
      application: 'V1.0 已上线，V2.0 迭代中，目标 8 月底发布',
    ),
    QianjiEntity(
      id: 'lh-bi',
      name: '灯塔经营分析',
      kind: QianjiEntityKind.platform,
      tag: 1,
      status: QianjiEntityStatus.online,
      owner: '陶枫',
      industryOrMode: '能源、零售',
      statusLabel: '已上线',
      application: '覆盖 12 省经营分析，日均活跃用户 200+',
    ),
    QianjiEntity(
      id: 'travel-unicom',
      name: '大出行 · 联通版',
      kind: QianjiEntityKind.platform,
      tag: 1,
      status: QianjiEntityStatus.online,
      owner: '徐峥',
      industryOrMode: '通信、政企',
      statusLabel: '已上线',
      application: '北京联通集团合作排期，多省会员覆盖',
    ),
    QianjiEntity(
      id: 'petro-channel',
      name: '石化营销渠道',
      kind: QianjiEntityKind.product,
      tag: 2,
      status: QianjiEntityStatus.developing,
      owner: '王磊',
      industryOrMode: '石化、三桶油',
      statusLabel: '研发中',
      application: '对外接口联调中，计划 Q3 接入营销中台',
    ),
    QianjiEntity(
      id: 'ai-minutes',
      name: 'AI 语音纪要',
      kind: QianjiEntityKind.capability,
      tag: 2,
      status: QianjiEntityStatus.online,
      owner: '李明',
      industryOrMode: '独立输出',
      statusLabel: '已上线',
      application: '2 小时交付 Word 纪要，央企现场演示',
      relatedProducts: '沙丘、千机',
    ),
    QianjiEntity(
      id: 'dune-collab',
      name: '沙丘协同平台',
      kind: QianjiEntityKind.product,
      tag: 3,
      status: QianjiEntityStatus.online,
      owner: '周工',
      industryOrMode: '全行业',
      statusLabel: '已上线',
      application: '审批流、任务协同已接入 20+ 内部系统',
    ),
    QianjiEntity(
      id: 'risk-engine',
      name: '智能风控引擎',
      kind: QianjiEntityKind.capability,
      tag: 3,
      status: QianjiEntityStatus.developing,
      owner: '赵敏',
      industryOrMode: '嵌入式',
      statusLabel: '研发中',
      application: '规则引擎 V2 升级，计划 Q3 试点上线',
      relatedProducts: '灯塔、石化',
    ),
  ];

  static List<QianjiEntity> forTag(int tag) =>
      entities.where((e) => e.tag == tag).toList(growable: false);

  static QianjiEntity? entityById(String id) {
    for (final e in entities) {
      if (e.id == id) return e;
    }
    return null;
  }

  static QianjiProductDetail detailFor(QianjiEntity entity) {
    if (entity.id == 'qj-platform') return _qjPlatformDetail;
    return _syntheticDetail(entity);
  }

  static QianjiIteration? iterationOf(QianjiEntity entity, String iterationId) {
    final detail = detailFor(entity);
    for (final it in detail.iterations) {
      if (it.id == iterationId) return it;
    }
    return detail.iterations.isEmpty ? null : detail.iterations.first;
  }

  static const _v2Iteration = QianjiIteration(
    id: 'v2',
    version: 'V2.0',
    statusLabel: '迭代中',
    active: true,
    phase: '联调测试',
    meta: '2026-06-01 立项 · 目标 2026-08-31 发布',
    owner: '杨静',
    members: '张三、朱子姝、李明、王磊',
    description:
        '聚焦提案审批、图谱交互与宿主 APP 菜单重构，在 V1.0 展厅能力基础上强化研发协同与沙丘审批对接。',
    ganttScale: ['5月', '6月', '7月', '8月', '9月'],
    ganttBars: [
      QianjiGanttBar(name: '需求立项', left: 0.00, width: 0.10, state: QianjiGanttState.done),
      QianjiGanttBar(name: '原型设计', left: 0.10, width: 0.18, state: QianjiGanttState.done),
      QianjiGanttBar(name: '开发实现', left: 0.28, width: 0.36, state: QianjiGanttState.done),
      QianjiGanttBar(name: '联调测试', left: 0.64, width: 0.18, state: QianjiGanttState.active),
      QianjiGanttBar(name: '上线发布', left: 0.82, width: 0.18, state: QianjiGanttState.pending),
    ],
    phases: [
      QianjiPhase(name: '需求立项', state: QianjiGanttState.done),
      QianjiPhase(name: '原型设计', state: QianjiGanttState.done),
      QianjiPhase(name: '开发实现', state: QianjiGanttState.done),
      QianjiPhase(name: '联调测试', state: QianjiGanttState.active),
      QianjiPhase(name: '上线发布', state: QianjiGanttState.pending),
    ],
    currentLabel: '当前 · 联调测试',
    nowPercent: 0.72,
    requirements: [
      QianjiRequirement(
        code: 'REQ-QJ-2026-0042',
        name: '千机平台 V2.0 提案审批与图谱交互迭代',
        phase: '联调测试',
      ),
      QianjiRequirement(
        code: 'REQ-QJ-2026-0038',
        name: '产品能力图谱 V2.0 力导向布局与标签筛选优化',
        phase: '开发实现',
      ),
    ],
    files: [
      QianjiDevFile(
        name: '千机平台 PRD v2.0.docx',
        size: '3.1 MB',
        icon: Icons.description_outlined,
        meta: 'PRD · 3.1 MB · 杨静 · 2026-06-12',
      ),
      QianjiDevFile(
        name: 'V2.0 迭代计划.pdf',
        size: '980 KB',
        icon: Icons.picture_as_pdf_outlined,
        meta: '计划 · 980 KB · 陈明 · 2026-06-01',
      ),
      QianjiDevFile(
        name: 'qianji-v2.0-beta.zip',
        size: '22.4 MB',
        icon: Icons.folder_zip_outlined,
        meta: '代码包 · 22.4 MB · 张三 · 2026-07-20',
      ),
    ],
    personChanges: [
      QianjiPersonChange(
        role: '负责人变更',
        from: '张磊',
        to: '杨静',
        time: '2026-06-02 · 组织架构调整',
      ),
      QianjiPersonChange(
        role: '研发成员变更',
        from: '王浩、陈晨',
        to: '张三、朱子姝',
        time: '2026-06-06 · 项目阶段切换',
      ),
      QianjiPersonChange(
        role: '研发成员新增',
        from: '张三、朱子姝',
        to: '张三、朱子姝、李明',
        time: '2026-06-10 · V2.0 立项扩编',
      ),
    ],
  );

  static const _v1Iteration = QianjiIteration(
    id: 'v1',
    version: 'V1.0',
    statusLabel: '已上线',
    active: false,
    phase: '',
    meta: '2025-03-15 立项 · 2026-05-30 发布',
    owner: '杨静',
    members: '张三、朱子姝、李明',
    description: 'V1.0 展厅与基础能力已上线，作为后续迭代基线。',
    ganttScale: ['3月', '6月', '9月', '12月', '5月'],
    ganttBars: [
      QianjiGanttBar(name: '需求立项', left: 0.00, width: 0.12, state: QianjiGanttState.done),
      QianjiGanttBar(name: '原型设计', left: 0.12, width: 0.18, state: QianjiGanttState.done),
      QianjiGanttBar(name: '开发实现', left: 0.30, width: 0.32, state: QianjiGanttState.done),
      QianjiGanttBar(name: '联调测试', left: 0.62, width: 0.16, state: QianjiGanttState.done),
      QianjiGanttBar(name: '上线发布', left: 0.78, width: 0.22, state: QianjiGanttState.done),
    ],
    phases: [
      QianjiPhase(name: '需求立项', state: QianjiGanttState.done),
      QianjiPhase(name: '原型设计', state: QianjiGanttState.done),
      QianjiPhase(name: '开发实现', state: QianjiGanttState.done),
      QianjiPhase(name: '联调测试', state: QianjiGanttState.done),
      QianjiPhase(name: '上线发布', state: QianjiGanttState.done),
    ],
    currentLabel: '已全部完成',
    requirements: const [],
    files: [
      QianjiDevFile(
        name: '千机平台 PRD v1.2.docx',
        size: '2.4 MB',
        icon: Icons.description_outlined,
      ),
      QianjiDevFile(
        name: '产品能力规格说明书.pdf',
        size: '1.8 MB',
        icon: Icons.picture_as_pdf_outlined,
      ),
      QianjiDevFile(
        name: 'qianji-platform-v1.0.zip 等 2 个',
        size: '24.8 MB',
        icon: Icons.folder_zip_outlined,
      ),
    ],
  );

  static final _qjPlatformDetail = QianjiProductDetail(
    entity: entities.first,
    description:
        'V2.0 迭代聚焦提案审批、图谱交互与宿主 APP 菜单重构，在 V1.0 展厅能力基础上强化研发协同与沙丘审批对接。',
    demoLabel: '千机 APP 演示页',
    statusLabel: '迭代中',
    capabilities: const [
      QianjiCapabilityLink(
        title: '产品能力图谱',
        description: 'V2.0 优化力导向布局与标签筛选，支持对外展厅按标签一/二/三分组展示。',
        status: '迭代中',
        icon: Icons.grid_view_rounded,
      ),
      QianjiCapabilityLink(
        title: '提案与任务协同',
        description: '新增/迭代两类审批填写，对接沙丘审批流，支持按标签拆分项目跟进。',
        status: '迭代中',
        icon: Icons.description_outlined,
      ),
      QianjiCapabilityLink(
        title: 'AI 语音纪要',
        description: 'V1.0 能力持续复用，V2.0 迭代无结构性变更。',
        status: '已上线',
        icon: Icons.mic_none_rounded,
      ),
    ],
    iterations: [_v2Iteration, _v1Iteration],
  );

  static QianjiProductDetail _syntheticDetail(QianjiEntity entity) {
    final iterating = entity.status == QianjiEntityStatus.developing;
    final active = iterating
        ? QianjiIteration(
            id: 'v2',
            version: 'V2.0',
            statusLabel: '迭代中',
            active: true,
            phase: '联调测试',
            meta: '2026-06-01 立项 · 目标 2026-08-31 发布',
            owner: entity.owner,
            members: '${entity.owner}、张三、李明',
            description: entity.application,
            ganttScale: _v2Iteration.ganttScale,
            ganttBars: _v2Iteration.ganttBars,
            phases: _v2Iteration.phases,
            currentLabel: '当前 · 联调测试',
            nowPercent: 0.72,
            requirements: [
              QianjiRequirement(
                code: 'REQ-QJ-2026-0100',
                name: '${entity.name} V2.0 迭代需求',
                phase: '联调测试',
              ),
            ],
            files: [
              QianjiDevFile(
                name: '${entity.name} PRD v2.0.docx',
                size: '2.0 MB',
                icon: Icons.description_outlined,
                meta: 'PRD · 2.0 MB · ${entity.owner} · 2026-06-12',
              ),
              QianjiDevFile(
                name: 'V2.0 迭代计划.pdf',
                size: '800 KB',
                icon: Icons.picture_as_pdf_outlined,
                meta: '计划 · 800 KB · 2026-06-01',
              ),
            ],
            personChanges: _v2Iteration.personChanges,
          )
        : QianjiIteration(
            id: 'v1',
            version: 'V1.0',
            statusLabel: '已上线',
            active: false,
            phase: '',
            meta: '2025-08-01 立项 · 2026-03-30 发布',
            owner: entity.owner,
            members: '${entity.owner}、张三、李明',
            description: entity.application,
            ganttScale: _v1Iteration.ganttScale,
            ganttBars: _v1Iteration.ganttBars,
            phases: _v1Iteration.phases,
            currentLabel: '已全部完成',
            requirements: const [],
            files: [
              QianjiDevFile(
                name: '${entity.name} 规格说明.pdf',
                size: '1.5 MB',
                icon: Icons.picture_as_pdf_outlined,
              ),
            ],
            personChanges: const [],
          );

    return QianjiProductDetail(
      entity: entity,
      description: entity.application,
      demoLabel: '${entity.name} 演示',
      statusLabel: iterating ? '迭代中' : '已上线',
      capabilities: [
        QianjiCapabilityLink(
          title: '核心能力',
          description: entity.application,
          status: iterating ? '迭代中' : '已上线',
          icon: entity.kindIcon,
        ),
      ],
      iterations: iterating ? [active, _copyV1For(entity)] : [active],
    );
  }

  static QianjiIteration _copyV1For(QianjiEntity entity) {
    return QianjiIteration(
      id: 'v1',
      version: 'V1.0',
      statusLabel: '已上线',
      active: false,
      phase: '',
      meta: '2025-03-15 立项 · 2026-05-30 发布',
      owner: entity.owner,
      members: '${entity.owner}、张三',
      description: '基线版本已上线。',
      ganttScale: _v1Iteration.ganttScale,
      ganttBars: _v1Iteration.ganttBars,
      phases: _v1Iteration.phases,
      currentLabel: '已全部完成',
      requirements: const [],
      files: [
        QianjiDevFile(
          name: '${entity.name} PRD v1.0.docx',
          size: '1.8 MB',
          icon: Icons.description_outlined,
        ),
      ],
    );
  }
}
