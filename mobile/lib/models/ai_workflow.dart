/// Interest tags the planner understands (same values as the web app).
const aiInterests = <String>[
  'beach',
  'nature',
  'culture',
  'adventure',
  'wildlife',
  'citylife',
];

const _interestLabels = <String, String>{
  'beach': 'Beach',
  'nature': 'Nature',
  'culture': 'Culture',
  'adventure': 'Adventure',
  'wildlife': 'Wildlife',
  'citylife': 'City life',
};

String interestLabel(String interest) =>
    _interestLabels[interest.toLowerCase()] ?? interest;

const _agentLabels = <String, String>{
  'planner': 'Planner',
  'destination': 'Destination research',
  'budget_availability': 'Budget & availability',
  'validation_safety': 'Validation & safety',
};

String agentLabel(String agentName) =>
    _agentLabels[agentName] ?? agentName.replaceAll('_', ' ');

/// What a traveler needs to know about a plan, derived from the workflow's
/// approval status and validation result.
enum AiOutcome {
  /// Passed every check; no operator review needed.
  ready('Ready', 'Your plan passed all checks and is ready.'),
  awaitingApproval(
      'Awaiting approval',
      'An operator is reviewing this plan. This page updates automatically '
          'once they decide.'),
  approved('Approved', 'An operator approved this plan.'),
  rejected('Rejected', 'An operator rejected this plan.'),
  revisionRequested('Revision requested',
      'An operator asked for changes. Plan again with an updated request.'),

  /// No approval needed, but the checks did not pass.
  flagged('Needs changes',
      'The checks found issues with this plan. Review the notes below or plan '
          'again.');

  final String label;
  final String message;
  const AiOutcome(this.label, this.message);

  factory AiOutcome.from(
      {required String approvalStatus, required String overallStatus}) {
    switch (approvalStatus) {
      case 'AwaitingApproval':
        return AiOutcome.awaitingApproval;
      case 'Approved':
        return AiOutcome.approved;
      case 'Rejected':
        return AiOutcome.rejected;
      case 'RevisionRequested':
        return AiOutcome.revisionRequested;
      default: // NotRequired (or anything unknown)
        return overallStatus == 'PASS' ? AiOutcome.ready : AiOutcome.flagged;
    }
  }

  bool get canPlanAgain =>
      this == rejected || this == revisionRequested || this == flagged;
}

/// Mirrors CEYLORA.Application.DTOs.AiWorkflows.AiWorkflowStepDto.
class AiWorkflowStep {
  final String id;
  final String agentName;
  final String status;
  final String? outputSummary;
  final String? errorMessage;

  const AiWorkflowStep({
    required this.id,
    required this.agentName,
    required this.status,
    this.outputSummary,
    this.errorMessage,
  });

  factory AiWorkflowStep.fromJson(Map<String, dynamic> json) => AiWorkflowStep(
        id: json['id'] as String,
        agentName: json['agentName'] as String,
        status: json['status'] as String,
        outputSummary: json['outputSummary'] as String?,
        errorMessage: json['errorMessage'] as String?,
      );

  bool get succeeded => status == 'completed';
  String get label => agentLabel(agentName);

  /// The line to show under the agent name.
  String? get detail {
    final text = succeeded ? outputSummary : (errorMessage ?? outputSummary);
    return (text == null || text.trim().isEmpty) ? null : text.trim();
  }
}

/// Mirrors CEYLORA.Application.DTOs.AiWorkflows.AiWorkflowResponseDto.
class AiWorkflow {
  final String id;
  final String goal;
  final int days;
  final double budget;
  final List<String> interests;
  final String? finalPlan;
  final String overallStatus;
  final String approvalStatus;
  final DateTime createdAt;
  final List<AiWorkflowStep> steps;

  const AiWorkflow({
    required this.id,
    required this.goal,
    required this.days,
    required this.budget,
    required this.interests,
    required this.finalPlan,
    required this.overallStatus,
    required this.approvalStatus,
    required this.createdAt,
    required this.steps,
  });

  factory AiWorkflow.fromJson(Map<String, dynamic> json) => AiWorkflow(
        id: json['id'] as String,
        goal: json['goal'] as String,
        days: (json['days'] as num).toInt(),
        budget: (json['budget'] as num).toDouble(),
        interests: ((json['interests'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
        finalPlan: json['finalPlan'] as String?,
        overallStatus: json['overallStatus'] as String,
        approvalStatus: json['approvalStatus'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        steps: ((json['steps'] as List<dynamic>?) ?? const [])
            .map((e) => AiWorkflowStep.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  AiOutcome get outcome => AiOutcome.from(
      approvalStatus: approvalStatus, overallStatus: overallStatus);
}
