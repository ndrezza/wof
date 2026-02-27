import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/git.js";
import { resolveOrg, requireProject } from "../config.js";

export function registerGitTools(server: McpServer) {
  server.tool(
    "get_file_content",
    "Get content of a file or directory from a repository",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      path: z.string().default("/").describe("Path to the file or folder"),
      version: z.string().optional().describe("The version (branch, tag, or commit) to get content from"),
      versionType: z.enum(["branch", "commit", "tag"]).optional().describe("Type of version specified"),
    },
    async ({ organizationId, projectId, repositoryId, path, version, versionType }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const content = await api.getFileContent(org, proj, repositoryId, {
          path,
          version,
          versionType,
        });
        return {
          content: [{ type: "text" as const, text: typeof content === "string" ? content : JSON.stringify(content, null, 2) }],
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
    "create_branch",
    "Create a new branch from an existing one. Pass plain branch names (no 'refs/heads/').",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      sourceBranch: z.string().describe("Name of the branch to copy from (without 'refs/heads/')"),
      newBranch: z.string().describe("Name of the new branch to create (without 'refs/heads/')"),
    },
    async ({ organizationId, projectId, repositoryId, sourceBranch, newBranch }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const result = await api.createBranch(org, proj, repositoryId, sourceBranch, newBranch);
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
    "create_commit",
    `Create a commit on an existing branch using file changes.
- Provide plain branch names (no "refs/heads/").
- Each file path may appear only once per commit request.
Provide changes as an array of objects with: changeType ("add", "edit", or "delete"), path, and content (for add/edit).`,
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      branchName: z.string().describe("The branch to commit to (without 'refs/heads/')"),
      commitMessage: z.string().describe("Commit message"),
      changes: z.array(z.object({
        changeType: z.enum(["add", "edit", "delete"]).describe("Type of change"),
        path: z.string().describe("File path"),
        content: z.string().optional().describe("File content (required for add/edit)"),
        contentType: z.enum(["rawtext", "base64"]).default("rawtext").describe("Content encoding"),
      })).describe("List of file changes"),
    },
    async ({ organizationId, projectId, repositoryId, branchName, commitMessage, changes }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const result = await api.createCommit(org, proj, repositoryId, branchName, commitMessage, changes);
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
    "list_commits",
    "List recent commits on a branch including file-level diff content for each commit",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      branchName: z.string().describe("Branch name to list commits from"),
      top: z.number().min(1).max(100).optional().describe("Maximum number of commits to return (Default: 10)"),
      skip: z.number().min(0).optional().describe("Number of commits to skip from the newest"),
    },
    async ({ organizationId, projectId, repositoryId, branchName, top, skip }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const commits = await api.listCommits(org, proj, repositoryId, branchName, { top, skip });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(commits, null, 2) }],
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
