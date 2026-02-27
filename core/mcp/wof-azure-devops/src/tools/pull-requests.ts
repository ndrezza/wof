import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/pull-requests.js";
import { resolveOrg, requireProject } from "../config.js";

export function registerPullRequestTools(server: McpServer) {
  server.tool(
    "list_pull_requests",
    "List pull requests in a repository",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      status: z.enum(["all", "active", "completed", "abandoned"]).optional().describe("Filter by pull request status"),
      creatorId: z.string().optional().describe("Filter by creator ID (must be a UUID)"),
      reviewerId: z.string().optional().describe("Filter by reviewer ID (must be a UUID)"),
      sourceRefName: z.string().optional().describe("Filter by source branch name"),
      targetRefName: z.string().optional().describe("Filter by target branch name"),
      top: z.number().default(10).optional().describe("Maximum number of pull requests to return (default: 10)"),
      skip: z.number().optional().describe("Number of pull requests to skip for pagination"),
    },
    async ({ organizationId, projectId, repositoryId, status, creatorId, reviewerId, sourceRefName, targetRefName, top, skip }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const prs = await api.listPullRequests(org, proj, repositoryId, {
          status,
          creatorId,
          reviewerId,
          sourceRefName,
          targetRefName,
          top,
          skip,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(prs, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pull_request",
    "Get details of a specific pull request",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      pullRequestId: z.number().describe("The ID of the pull request"),
    },
    async ({ organizationId, projectId, repositoryId, pullRequestId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const pr = await api.getPullRequest(org, proj, repositoryId, pullRequestId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(pr, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "create_pull_request",
    "Create a new pull request, including reviewers, linked work items, and optional tags",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      title: z.string().describe("The title of the pull request"),
      description: z.string().optional().describe("The description (markdown supported)"),
      sourceRefName: z.string().describe("The source branch name (e.g., refs/heads/feature-branch)"),
      targetRefName: z.string().describe("The target branch name (e.g., refs/heads/main)"),
      reviewers: z.array(z.string()).optional().describe("List of reviewer email addresses or IDs"),
      isDraft: z.boolean().optional().describe("Whether to create as a draft"),
      workItemRefs: z.array(z.number()).optional().describe("List of work item IDs to link"),
      tags: z.array(z.string()).optional().describe("List of tags to apply"),
    },
    async ({ organizationId, projectId, repositoryId, title, description, sourceRefName, targetRefName, reviewers, isDraft, workItemRefs, tags }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const pr = await api.createPullRequest(org, proj, repositoryId, {
          title,
          description,
          sourceRefName,
          targetRefName,
          reviewers,
          isDraft,
          workItemRefs,
          labels: tags,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(pr, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "update_pull_request",
    "Update an existing pull request",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      pullRequestId: z.number().describe("The ID of the pull request"),
      title: z.string().optional().describe("Updated title"),
      description: z.string().optional().describe("Updated description"),
      status: z.string().optional().describe("Updated status (active, abandoned, completed)"),
      targetRefName: z.string().optional().describe("Updated target branch"),
      isDraft: z.boolean().optional().describe("Updated draft status"),
    },
    async ({ organizationId, projectId, repositoryId, pullRequestId, title, description, status, targetRefName, isDraft }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const pr = await api.updatePullRequest(org, proj, repositoryId, pullRequestId, {
          title,
          description,
          status,
          targetRefName,
          isDraft,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(pr, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pull_request_comments",
    "Get all comment threads on a pull request",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      pullRequestId: z.number().describe("The ID of the pull request"),
    },
    async ({ organizationId, projectId, repositoryId, pullRequestId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const threads = await api.getPullRequestComments(org, proj, repositoryId, pullRequestId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(threads, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "add_pull_request_comment",
    "Add a comment to a pull request (new thread or reply to existing)",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      pullRequestId: z.number().describe("The ID of the pull request"),
      content: z.string().describe("The comment content"),
      threadId: z.number().optional().describe("Reply to an existing thread ID"),
      parentCommentId: z.number().optional().describe("Reply to a specific comment within a thread"),
      filePath: z.string().optional().describe("File path for inline comments"),
      lineNumber: z.number().optional().describe("Line number for inline comments"),
      status: z.string().optional().describe("Thread status ('active' or 'closed')"),
    },
    async ({ organizationId, projectId, repositoryId, pullRequestId, content, threadId, parentCommentId, filePath, lineNumber, status }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const result = await api.addPullRequestComment(org, proj, repositoryId, pullRequestId, content, {
          threadId,
          parentCommentId,
          filePath,
          lineNumber,
          status,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pull_request_changes",
    "Get the file changes in a pull request",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      pullRequestId: z.number().describe("The ID of the pull request"),
    },
    async ({ organizationId, projectId, repositoryId, pullRequestId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const changes = await api.getPullRequestChanges(org, proj, repositoryId, pullRequestId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(changes, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pull_request_checks",
    "Summarize the latest status checks and policy evaluations for a pull request",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      pullRequestId: z.number().describe("The ID of the pull request"),
    },
    async ({ organizationId, projectId, repositoryId, pullRequestId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const checks = await api.getPullRequestChecks(org, proj, repositoryId, pullRequestId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(checks, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );
}
