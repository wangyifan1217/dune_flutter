import 'package:flutter/material.dart';

import 'qianji_perf_shared.dart';

enum QianjiProjectStatus { running, done, late }

enum QianjiProjectRole { owner, developer, late }

enum QianjiTaskStatus { running, done, pending }

class QianjiProjectItem {
  const QianjiProjectItem({
    required this.id,
    required this.name,
    required this.meta,
    required this.statusLabel,
    required this.status,
    required this.role,
    required this.roleLabel,
    required this.progress,
    required this.taskSummary,
    required this.deadline,
    required this.icon,
    required this.owned,
  });

  final String id;
  final String name;
  final String meta;
  final String statusLabel;
  final QianjiProjectStatus status;
  final QianjiProjectRole role;
  final String roleLabel;
  final double progress;
  final String taskSummary;
  final String deadline;
  final IconData icon;
  final bool owned;
}

class QianjiTaskItem {
  const QianjiTaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.tags,
    required this.due,
    this.assignee,
    this.mine = false,
    this.warn = false,
    this.canComplete = false,
  });

  final String id;
  final String title;
  final QianjiTaskStatus status;
  final String statusLabel;
  final List<String> tags;
  final String due;
  final String? assignee;
  final bool mine;
  final bool warn;
  final bool canComplete;
}

class QianjiTaskFeed {
  const QianjiTaskFeed({
    required this.who,
    required this.time,
    required this.type,
    required this.content,
    this.up = false,
  });

  final String who;
  final String time;
  final String type;
  final String content;
  final bool up;
}

class QianjiTaskMember {
  const QianjiTaskMember({
    required this.name,
    required this.role,
    required this.commit,
    required this.days,
    required this.color,
  });

  final String name;
  final String role;
  final String commit;
  final String days;
  final Color color;
}

class QianjiSubTask {
  const QianjiSubTask({
    required this.name,
    required this.assignee,
    required this.due,
    required this.percent,
    required this.done,
    this.running = false,
    this.warn = false,
  });

  final String name;
  final String assignee;
  final String due;
  final int percent;
  final bool done;
  final bool running;
  final bool warn;
}

class QianjiTaskAttachment {
  const QianjiTaskAttachment({
    required this.name,
    required this.meta,
    required this.icon,
    required this.color,
    required this.bg,
  });

  final String name;
  final String meta;
  final IconData icon;
  final Color color;
  final Color bg;
}

class QianjiTaskDetail {
  const QianjiTaskDetail({
    required this.id,
    required this.titleLines,
    required this.owner,
    required this.due,
    required this.branch,
    required this.progress,
    required this.subDone,
    required this.subTotal,
    required this.usedDays,
    required this.totalDays,
    required this.remainDays,
    required this.weekCommits,
    required this.info,
    required this.members,
    required this.subTasks,
    required this.attachments,
    required this.feeds,
  });

  final String id;
  final List<String> titleLines;
  final String owner;
  final String due;
  final String branch;
  final double progress;
  final int subDone;
  final int subTotal;
  final int usedDays;
  final int totalDays;
  final int remainDays;
  final int weekCommits;
  final Map<String, String> info;
  final List<QianjiTaskMember> members;
  final List<QianjiSubTask> subTasks;
  final List<QianjiTaskAttachment> attachments;
  final List<QianjiTaskFeed> feeds;
}

class QianjiProjectDetail {
  const QianjiProjectDetail({
    required this.project,
    required this.bannerTitle,
    required this.role,
    required this.deadline,
    required this.branch,
    required this.myTasks,
    required this.otherTasks,
    required this.feeds,
    required this.taskDetail,
  });

  final QianjiProjectItem project;
  final String bannerTitle;
  final String role;
  final String deadline;
  final String branch;
  final List<QianjiTaskItem> myTasks;
  final List<QianjiTaskItem> otherTasks;
  final List<QianjiTaskFeed> feeds;
  final QianjiTaskDetail taskDetail;
}

/// 07 / 08 / 09 静态样例。
abstract final class QianjiProjectCatalog {
  static const owned = [
    QianjiProjectItem(
      id: 'qj-platform',
      name: '千机平台',
      meta: '产品负责人 · 6 项能力 · V2.0 迭代中',
      statusLabel: '研发中',
      status: QianjiProjectStatus.running,
      role: QianjiProjectRole.owner,
      roleLabel: '负责人',
      progress: 0.58,
      taskSummary: '✓ 8 完成  ·  ▶ 2 进行中',
      deadline: '截止 07-31',
      icon: Icons.inventory_2_outlined,
      owned: true,
    ),
    QianjiProjectItem(
      id: 'mirror-ai',
      name: 'Mirror AI 智能体',
      meta: '产品负责人 · 已上线 · 3 月交付',
      statusLabel: '已完成',
      status: QianjiProjectStatus.done,
      role: QianjiProjectRole.owner,
      roleLabel: '负责人',
      progress: 1,
      taskSummary: '✓ 全部完成',
      deadline: '03-15 交付',
      icon: Icons.psychology_outlined,
      owned: true,
    ),
  ];

  static const joined = [
    QianjiProjectItem(
      id: 'lh-cut',
      name: '灯塔数据切割',
      meta: '开发人员 · 超期 10 天 · 4 子任务待完成',
      statusLabel: '已延期',
      status: QianjiProjectStatus.late,
      role: QianjiProjectRole.late,
      roleLabel: '延期',
      progress: 0.62,
      taskSummary: '✓ 5 完成  ·  ⚠ 3 延期',
      deadline: '超期 05-20',
      icon: Icons.show_chart_rounded,
      owned: false,
    ),
    QianjiProjectItem(
      id: 'voice-prd',
      name: '语音纪要 PRD',
      meta: '开发人员 · 测试阶段 · 联调中',
      statusLabel: '进行中',
      status: QianjiProjectStatus.running,
      role: QianjiProjectRole.developer,
      roleLabel: '开发者',
      progress: 0.78,
      taskSummary: '✓ 7 完成  ·  ▶ 2 进行',
      deadline: '截止 06-30',
      icon: Icons.mic_none_rounded,
      owned: false,
    ),
  ];

  static QianjiProjectItem? byId(String id) {
    for (final p in [...owned, ...joined]) {
      if (p.id == id) return p;
    }
    return null;
  }

  static QianjiProjectDetail detailFor(QianjiProjectItem project) {
    if (project.id == 'voice-prd') return _voicePrd;
    return _synthetic(project);
  }

  static final _voicePrd = QianjiProjectDetail(
    project: joined.last,
    bannerTitle: '语音纪要 PRD 生成系统',
    role: '前端开发',
    deadline: '截止 06-30',
    branch: 'dev/v1.2',
    myTasks: const [
      QianjiTaskItem(
        id: 't-webrtc',
        title: '前端语音控件重构 · WebRTC 接入',
        status: QianjiTaskStatus.running,
        statusLabel: '进行中',
        tags: ['前端', 'P0'],
        due: '06-18 截止',
        mine: true,
        warn: true,
        canComplete: true,
      ),
      QianjiTaskItem(
        id: 't-poc',
        title: 'WebRTC 权限申请模块 · POC 验证',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['前端'],
        due: '06-08 完成',
        mine: true,
      ),
    ],
    otherTasks: const [
      QianjiTaskItem(
        id: 't-md',
        title: 'PRD 模板渲染引擎 · Markdown 输出',
        status: QianjiTaskStatus.running,
        statusLabel: '进行中',
        tags: ['前端', 'P1'],
        due: '06-25 截止',
        assignee: '朱子姝',
      ),
      QianjiTaskItem(
        id: 't-asr',
        title: '语音 ASR 接口封装',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['后端'],
        due: '06-05 完成',
        assignee: '李明',
      ),
      QianjiTaskItem(
        id: 't-nlp',
        title: 'NLP 关键词抽取模块',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['算法'],
        due: '06-02 完成',
        assignee: '李明',
      ),
      QianjiTaskItem(
        id: 't-uat',
        title: '用户验收测试 · UAT 场景脚本',
        status: QianjiTaskStatus.pending,
        statusLabel: '待开始',
        tags: ['测试'],
        due: '计划 06-26',
        assignee: '刘洋',
      ),
      QianjiTaskItem(
        id: 't-compat',
        title: '三端兼容性测试 Chrome/Safari/Edge',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['前端'],
        due: '06-08 完成',
        assignee: '朱子姝',
      ),
      QianjiTaskItem(
        id: 't-nls',
        title: 'ASR 接口联调 · 阿里云 NLS',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['后端'],
        due: '06-10 完成',
        assignee: '李明',
      ),
      QianjiTaskItem(
        id: 't-struct',
        title: '会议纪要结构化解析模块',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['后端'],
        due: '06-06 完成',
        assignee: '王磊',
      ),
      QianjiTaskItem(
        id: 't-denoise',
        title: '降噪滤波 WebAudio 工作流搭建',
        status: QianjiTaskStatus.done,
        statusLabel: '已完成',
        tags: ['前端'],
        due: '06-12 完成',
        assignee: '张三',
      ),
      QianjiTaskItem(
        id: 't-reconnect',
        title: '断网重连逻辑 + 压测脚本',
        status: QianjiTaskStatus.pending,
        statusLabel: '待开始',
        tags: ['前端'],
        due: '计划 06-18',
        assignee: '朱子姝',
      ),
    ],
    feeds: const [
      QianjiTaskFeed(
        who: '李明',
        time: '06-10 16:40',
        type: '提交任务',
        content: '完成子任务「ASR 接口联调 · 阿里云 NLS」',
      ),
      QianjiTaskFeed(
        who: '朱子姝',
        time: '06-08 11:15',
        type: '提交任务',
        content: '完成子任务「三端兼容性测试 Chrome/Safari/Edge」',
      ),
      QianjiTaskFeed(
        who: '张三',
        time: '06-05 14:30',
        type: '提交任务',
        content: '完成子任务「AudioContext 采样率配置 · 16kHz 标准化」',
      ),
      QianjiTaskFeed(
        who: '张三',
        time: '06-03 17:20',
        type: '提交任务',
        content: '完成子任务「WebRTC getUserMedia 权限申请封装」',
      ),
      QianjiTaskFeed(
        who: '张三',
        time: '06-02 09:15',
        type: '提交任务',
        content: '启动子任务「WebRTC getUserMedia 权限申请封装」，分支 feat/webrtc-refactor 已创建。',
        up: true,
      ),
    ],
    taskDetail: QianjiTaskDetail(
      id: 't-webrtc',
      titleLines: ['前端语音控件重构', 'WebRTC 实时接入'],
      owner: '张三',
      due: '06-18 截止',
      branch: 'feat/webrtc',
      progress: 0.65,
      subDone: 4,
      subTotal: 6,
      usedDays: 13,
      totalDays: 20,
      remainDays: 6,
      weekCommits: 8,
      info: {
        '任务编号': 'TASK-2026-0612',
        '项目名称': '语音纪要 PRD',
        '优先级': 'P0 · 紧急',
        '负责人': '张三',
        '参与成员': '朱子姝、李明',
        '开始日期': '2026-06-01',
        '截止日期': '2026-06-18 ⚠',
        '预估工时': '20 人天',
        '已用工时': '13 人天',
        '代码分支': 'feat/webrtc-refactor',
        '关联提案': 'V2.0 产品迭代提案',
      },
      members: const [
        QianjiTaskMember(
          name: '张三',
          role: '前端开发 · 任务负责人',
          commit: '100%',
          days: '10 天投入',
          color: Color(0xFF1D9E75),
        ),
        QianjiTaskMember(
          name: '朱子姝',
          role: '前端开发 · 协作成员',
          commit: '60%',
          days: '6 天投入',
          color: QianjiPerfTheme.purple,
        ),
        QianjiTaskMember(
          name: '李明',
          role: '后端开发 · 接口对接',
          commit: '30%',
          days: '3 天投入',
          color: Color(0xFFBA7517),
        ),
      ],
      subTasks: const [
        QianjiSubTask(
          name: 'WebRTC getUserMedia 权限申请封装',
          assignee: '张三',
          due: '06-03',
          percent: 100,
          done: true,
        ),
        QianjiSubTask(
          name: 'AudioContext 采样率配置 · 16kHz 标准化',
          assignee: '张三',
          due: '06-05',
          percent: 100,
          done: true,
        ),
        QianjiSubTask(
          name: '三端兼容性测试 Chrome/Safari/Edge',
          assignee: '朱子姝',
          due: '06-08',
          percent: 100,
          done: true,
        ),
        QianjiSubTask(
          name: 'ASR 接口联调 · 阿里云 NLS',
          assignee: '李明',
          due: '06-10',
          percent: 100,
          done: true,
        ),
        QianjiSubTask(
          name: '降噪滤波 WebAudio 工作流搭建',
          assignee: '张三',
          due: '06-16',
          percent: 50,
          done: false,
          running: true,
          warn: true,
        ),
        QianjiSubTask(
          name: '断网重连逻辑 + 压测脚本',
          assignee: '朱子姝',
          due: '06-18',
          percent: 0,
          done: false,
        ),
      ],
      attachments: const [
        QianjiTaskAttachment(
          name: 'WebRTC_技术方案_v2.1.pdf',
          meta: '3.2 MB · 张三 · 06-02',
          icon: Icons.picture_as_pdf_outlined,
          color: Color(0xFFE07B39),
          bg: Color(0xFFFFF0E6),
        ),
        QianjiTaskAttachment(
          name: '语音控件接口规范.docx',
          meta: '680 KB · 李明 · 06-05',
          icon: Icons.description_outlined,
          color: Color(0xFF185FA5),
          bg: Color(0xFFE6F1FB),
        ),
        QianjiTaskAttachment(
          name: '兼容性测试报告.xlsx',
          meta: '240 KB · 朱子姝 · 06-08',
          icon: Icons.table_chart_outlined,
          color: Color(0xFF5D8A4E),
          bg: Color(0xFFEAEFDF),
        ),
        QianjiTaskAttachment(
          name: 'webrtc-demo.zip · 原型代码',
          meta: '1.8 MB · 张三 · 06-10',
          icon: Icons.folder_zip_outlined,
          color: QianjiPerfTheme.purple,
          bg: QianjiPerfTheme.purpleSoft,
        ),
      ],
      feeds: [
        QianjiTaskFeed(
          who: '李明',
          time: '06-10 16:40',
          type: '提交任务',
          content: '完成子任务「ASR 接口联调 · 阿里云 NLS」',
        ),
        QianjiTaskFeed(
          who: '朱子姝',
          time: '06-08 11:15',
          type: '提交任务',
          content: '完成子任务「三端兼容性测试 Chrome/Safari/Edge」',
        ),
        QianjiTaskFeed(
          who: '张三',
          time: '06-05 14:30',
          type: '提交任务',
          content: '完成子任务「AudioContext 采样率配置 · 16kHz 标准化」',
        ),
        QianjiTaskFeed(
          who: '张三',
          time: '06-03 17:20',
          type: '提交任务',
          content: '完成子任务「WebRTC getUserMedia 权限申请封装」',
        ),
        QianjiTaskFeed(
          who: '张三',
          time: '06-02 09:15',
          type: '提交任务',
          content: '启动子任务「WebRTC getUserMedia 权限申请封装」，分支 feat/webrtc-refactor 已创建。',
          up: true,
        ),
      ],
    ),
  );

  static QianjiProjectDetail _synthetic(QianjiProjectItem project) {
    final base = _voicePrd;
    return QianjiProjectDetail(
      project: project,
      bannerTitle: project.name,
      role: project.owned ? '产品负责人' : '开发人员',
      deadline: project.deadline,
      branch: 'dev/main',
      myTasks: [
        QianjiTaskItem(
          id: '${project.id}-mine',
          title: '${project.name} · 当前迭代任务',
          status: project.status == QianjiProjectStatus.done
              ? QianjiTaskStatus.done
              : QianjiTaskStatus.running,
          statusLabel:
              project.status == QianjiProjectStatus.done ? '已完成' : '进行中',
          tags: const ['研发'],
          due: project.deadline,
          mine: true,
          canComplete: project.status != QianjiProjectStatus.done,
        ),
      ],
      otherTasks: base.otherTasks.take(3).toList(growable: false),
      feeds: base.feeds,
      taskDetail: QianjiTaskDetail(
        id: '${project.id}-mine',
        titleLines: [project.name, '当前迭代任务'],
        owner: '张三',
        due: project.deadline,
        branch: 'feat/${project.id}',
        progress: project.progress,
        subDone: (project.progress * 6).round().clamp(0, 6),
        subTotal: 6,
        usedDays: 10,
        totalDays: 20,
        remainDays: 8,
        weekCommits: 5,
        info: {
          '任务编号': 'TASK-${project.id.toUpperCase()}',
          '项目名称': project.name,
          '优先级': 'P1',
          '负责人': '张三',
          '参与成员': '李明、朱子姝',
          '开始日期': '2026-05-01',
          '截止日期': project.deadline,
          '预估工时': '20 人天',
          '已用工时': '10 人天',
          '代码分支': 'feat/${project.id}',
          '关联提案': '产品迭代提案',
        },
        members: base.taskDetail.members,
        subTasks: base.taskDetail.subTasks,
        attachments: base.taskDetail.attachments,
        feeds: base.feeds,
      ),
    );
  }
}
