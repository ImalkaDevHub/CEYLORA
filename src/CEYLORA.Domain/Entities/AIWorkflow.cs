namespace CEYLORA.Domain.Entities;

public enum ApprovalStatus
{
    /// <summary>Workflow passed validation and is below the approval threshold — no gate needed.</summary>
    NotRequired,

    /// <summary>Sitting in the operator queue, waiting for a human decision.</summary>
    AwaitingApproval,

    /// <summary>An operator/admin approved it.</summary>
    Approved,

    /// <summary>An operator/admin rejected it outright.</summary>
    Rejected,

    /// <summary>
    /// An operator/admin sent it back for changes. Terminal for this workflow row —
    /// the traveler resubmits, which starts a new workflow.
    /// </summary>
    RevisionRequested
}

/// <summary>
/// One end-to-end run of the agentic planning chain in ceylora-ai-service,
/// persisted here so the run is auditable and can be gated on human approval.
/// </summary>
public class AIWorkflow
{
    public Guid Id { get; set; }

    // Nullable: a workflow can be run for planning before any Trip row exists.
    public Guid? TripId { get; set; }
    public Trip? Trip { get; set; }

    public Guid TravelerId { get; set; }
    public User Traveler { get; set; } = null!;

    public string Goal { get; set; } = string.Empty;
    public int Days { get; set; }
    public decimal Budget { get; set; }

    // Persisted as a comma-separated string via a value converter (see ApplicationDbContext).
    public List<string> Interests { get; set; } = new();

    public string? FinalPlan { get; set; }

    /// <summary>Verdict from the validation_safety agent: "Pending", "PASS" or "NEEDS_REVISION".</summary>
    public string OverallStatus { get; set; } = "Pending";

    public bool RequiresApproval { get; set; }
    public ApprovalStatus ApprovalStatus { get; set; } = ApprovalStatus.NotRequired;

    public Guid? ApprovedByUserId { get; set; }
    public User? ApprovedByUser { get; set; }
    public DateTime? ApprovedAt { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? CompletedAt { get; set; }

    public ICollection<AIWorkflowStep> Steps { get; set; } = new List<AIWorkflowStep>();
}
