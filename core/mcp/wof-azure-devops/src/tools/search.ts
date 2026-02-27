import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/search.js";
import { resolveOrg, resolveProject } from "../config.js";

export function registerSearchTools(server: McpServer) {
  server.tool(
    "search_code",
    "Search for code across repositories in a project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      searchText: z.string().describe("The text to search for"),
      top: z.number().min(1).max(1000).default(100).optional().describe("Number of results to return (default: 100, max: 1000)"),
      skip: z.number().min(0).default(0).optional().describe("Number of results to skip for pagination"),
      includeSnippet: z.boolean().default(true).optional().describe("Whether to include code snippets"),
      includeContent: z.boolean().default(true).optional().describe("Whether to include full file content"),
      filters: z.object({
        Repository: z.array(z.string()).optional().describe("Filter by repository names"),
        Path: z.array(z.string()).optional().describe("Filter by file paths"),
        Branch: z.array(z.string()).optional().describe("Filter by branch names"),
        CodeElement: z.array(z.string()).optional().describe("Filter by code element types"),
      }).optional().describe("Optional filters to narrow search results"),
    },
    async ({ organizationId, projectId, searchText, top, skip, includeSnippet, includeContent, filters }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        if (!proj) throw new Error("projectId is required for code search");
        const result = await api.searchCode(org, proj, searchText, {
          top,
          skip,
          includeSnippet,
          includeContent,
          filters,
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
    "search_wiki",
    "Search for content across wiki pages in a project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      searchText: z.string().describe("The text to search for in wikis"),
      top: z.number().min(1).max(1000).default(100).optional().describe("Number of results to return"),
      skip: z.number().min(0).default(0).optional().describe("Number of results to skip"),
      includeFacets: z.boolean().default(true).optional().describe("Whether to include faceting"),
      filters: z.object({
        Project: z.array(z.string()).optional().describe("Filter by project names"),
      }).optional().describe("Optional filters"),
    },
    async ({ organizationId, projectId, searchText, top, skip, includeFacets, filters }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        const result = await api.searchWiki(org, proj, searchText, {
          top,
          skip,
          includeFacets,
          filters,
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
    "search_work_items",
    "Search for work items across projects in Azure DevOps",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      searchText: z.string().describe("The text to search for in work items"),
      top: z.number().min(1).max(1000).default(100).optional().describe("Number of results to return"),
      skip: z.number().min(0).default(0).optional().describe("Number of results to skip"),
      includeFacets: z.boolean().default(true).optional().describe("Whether to include faceting"),
      orderBy: z.array(z.object({
        field: z.string().describe("Field to sort by"),
        sortOrder: z.enum(["ASC", "DESC"]).describe("Sort order"),
      })).optional().describe("Sort options"),
      filters: z.object({
        "System.TeamProject": z.array(z.string()).optional().describe("Filter by project names"),
        "System.WorkItemType": z.array(z.string()).optional().describe("Filter by work item types"),
        "System.State": z.array(z.string()).optional().describe("Filter by states"),
        "System.AssignedTo": z.array(z.string()).optional().describe("Filter by assigned users"),
        "System.AreaPath": z.array(z.string()).optional().describe("Filter by area paths"),
      }).optional().describe("Optional filters"),
    },
    async ({ organizationId, projectId, searchText, top, skip, includeFacets, orderBy, filters }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        const result = await api.searchWorkItems(org, proj, searchText, {
          top,
          skip,
          includeFacets,
          orderBy,
          filters,
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
}
