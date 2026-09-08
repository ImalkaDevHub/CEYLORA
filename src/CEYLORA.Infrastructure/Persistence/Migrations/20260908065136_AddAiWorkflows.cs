using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CEYLORA.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAiWorkflows : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AIWorkflows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TripId = table.Column<Guid>(type: "uuid", nullable: true),
                    TravelerId = table.Column<Guid>(type: "uuid", nullable: false),
                    Goal = table.Column<string>(type: "text", nullable: false),
                    Days = table.Column<int>(type: "integer", nullable: false),
                    Budget = table.Column<decimal>(type: "numeric", nullable: false),
                    Interests = table.Column<string>(type: "text", nullable: false),
                    FinalPlan = table.Column<string>(type: "text", nullable: true),
                    OverallStatus = table.Column<string>(type: "text", nullable: false),
                    RequiresApproval = table.Column<bool>(type: "boolean", nullable: false),
                    ApprovalStatus = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    ApprovedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ApprovedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AIWorkflows", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AIWorkflows_Trips_TripId",
                        column: x => x.TripId,
                        principalTable: "Trips",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_AIWorkflows_Users_ApprovedByUserId",
                        column: x => x.ApprovedByUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_AIWorkflows_Users_TravelerId",
                        column: x => x.TravelerId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "AIWorkflowSteps",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AIWorkflowId = table.Column<Guid>(type: "uuid", nullable: false),
                    AgentName = table.Column<string>(type: "text", nullable: false),
                    Status = table.Column<string>(type: "text", nullable: false),
                    StartedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    OutputSummary = table.Column<string>(type: "text", nullable: true),
                    ErrorMessage = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AIWorkflowSteps", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AIWorkflowSteps_AIWorkflows_AIWorkflowId",
                        column: x => x.AIWorkflowId,
                        principalTable: "AIWorkflows",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AIWorkflows_ApprovalStatus",
                table: "AIWorkflows",
                column: "ApprovalStatus");

            migrationBuilder.CreateIndex(
                name: "IX_AIWorkflows_ApprovedByUserId",
                table: "AIWorkflows",
                column: "ApprovedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AIWorkflows_TravelerId",
                table: "AIWorkflows",
                column: "TravelerId");

            migrationBuilder.CreateIndex(
                name: "IX_AIWorkflows_TripId",
                table: "AIWorkflows",
                column: "TripId");

            migrationBuilder.CreateIndex(
                name: "IX_AIWorkflowSteps_AIWorkflowId",
                table: "AIWorkflowSteps",
                column: "AIWorkflowId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AIWorkflowSteps");

            migrationBuilder.DropTable(
                name: "AIWorkflows");
        }
    }
}
