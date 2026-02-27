import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/repositories.js";
import { resolveOrg, resolveProject } from "../config.js";

export function registerRepositoryTools(server: McpServer) {
  server.tool(
    "list_repositories",
    "List all Git repositories in a project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
    },
    async ({ organizationId, projectId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        const repos = await api.listRepositories(org, proj);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(repos, null, 2) }],
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
    "get_repository",
    "Get details of a specific repository",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
    },
    async ({ organizationId, projectId, repositoryId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        const repo = await api.getRepository(org, repositoryId, proj);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(repo, null, 2) }],
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
    "get_repository_details",
    "Get detailed information about a repository including statistics and refs",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      includeRefs: z.boolean().default(false).describe("Whether to include repository refs"),
      includeStatistics: z.boolean().default(false).describe("Whether to include branch statistics"),
      branchName: z.string().optional().describe("Name of specific branch to get statistics for"),
      refFilter: z.string().optional().describe("Optional filter for refs (e.g., 'heads/' or 'tags/')"),
    },
    async ({ organizationId, projectId, repositoryId, includeRefs, includeStatistics, branchName, refFilter }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        const result = await api.getRepositoryDetails(org, repositoryId, proj, {
          includeRefs,
          includeStatistics,
          branchName,
          refFilter,
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
    "get_repository_tree",
    "Displays a hierarchical tree view of files and directories within a single repository",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      repositoryId: z.string().describe("The ID or name of the repository"),
      path: z.string().default("/").describe("Path within the repository to start from"),
      depth: z.number().min(0).max(10).default(0).describe("Maximum depth to traverse (0 = unlimited)"),
    },
    async ({ organizationId, projectId, repositoryId, path, depth }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        if (!proj) throw new Error("projectId is required");
        const items = await api.getRepositoryTree(org, repositoryId, proj, { path, depth });

        // Format as tree view
        const lines = items.map((item) => {
          const indent = item.relativePath.split("/").length - 1;
          const prefix = item.gitObjectType === "tree" ? "📁" : "📄";
          return `${"  ".repeat(indent)}${prefix} ${item.relativePath}`;
        });

        return {
          content: [{ type: "text" as const, text: lines.join("\n") || "Empty repository" }],
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
    "get_all_repositories_tree",
    "Displays a hierarchical tree view of files and directories for all repositories in a project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      depth: z.number().min(0).max(10).default(0).describe("Maximum depth to traverse (0 = unlimited)"),
    },
    async ({ organizationId, projectId, depth }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        if (!proj) throw new Error("projectId is required");
        const results = await api.getAllRepositoriesTree(org, proj, { depth });

        const output = results.map((r) => {
          const header = `\n=== ${r.repository} ===`;
          if (!r.items.length) return `${header}\n  (empty)`;
          const lines = r.items.map((item) => {
            const indent = item.relativePath.split("/").length - 1;
            const prefix = item.gitObjectType === "tree" ? "📁" : "📄";
            return `  ${"  ".repeat(indent)}${prefix} ${item.relativePath}`;
          });
          return `${header}\n${lines.join("\n")}`;
        });

        return {
          content: [{ type: "text" as const, text: output.join("\n") || "No repositories found" }],
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
