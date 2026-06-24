class ApprovalTodoItem {
  const ApprovalTodoItem({
    required this.id,
    required this.businessType,
    required this.businessId,
    required this.status,
    required this.kind,
    this.title,
    this.subtitle,
  });

  final int id;
  final String businessType;
  final int businessId;
  final String status;
  final String kind;
  final String? title;
  final String? subtitle;
}

class ApprovalStep {
  const ApprovalStep({
    required this.stepNo,
    required this.stepName,
    required this.decision,
    required this.assigneeName,
    required this.comment,
    required this.updatedAt,
  });

  final int stepNo;
  final String stepName;
  final String decision;
  final String assigneeName;
  final String comment;
  final DateTime? updatedAt;
}

class ApprovalDetailPayload {
  const ApprovalDetailPayload({
    required this.proposalId,
    required this.status,
    required this.title,
    required this.summary,
    required this.steps,
  });

  final int proposalId;
  final String status;
  final String title;
  final String summary;
  final List<ApprovalStep> steps;
}
