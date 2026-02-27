import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/projects.js";
import { resolveOrg, resolveProject } from "../config.js";

export function registerProjectTools(server: McpServer) {
  server.tool(
    "list_projects",
    "List all projects in an organization",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      top: z.number().optional().describe("Maximum number of projects to return"),
      skip: z.number().optional().describe("Number of projects to skip"),
      stateFilter: z.number().optional().describe("Filter on team project state (0: all, 1: well-formed, 2: creating, 3: deleting, 4: new)"),
      continuationToken: z.number().optional().describe("Gets the projects after the continuation token provided"),
    },
    async ({ organizationId, top, skip, stateFilter, continuationToken }) => {
      try {
        const org = resolveOrg(organizationId);
        const result = await api.listProjects(org, { top, skip, stateFilter, continuationToken });
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
    "get_project",
    "Get details of a specific project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
    },
    async ({ organizationId, projectId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        if (!proj) throw new Error("projectId is required");
        const result = await api.getProject(org, proj);
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
    "get_project_details",
    "Get comprehensive details of a project including process, work item types, and teams",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      includeProcess: z.boolean().default(false).describe("Include process information in the project result"),
      includeTeams: z.boolean().default(false).describe("Include associated teams in the project result"),
      includeWorkItemTypes: z.boolean().default(false).describe("Include work item types and their structure"),
      includeFields: z.boolean().default(false).describe("Include field information for work item types"),
      expandTeamIdentity: z.boolean().default(false).describe("Expand identity information in the team objects"),
    },
    async ({ organizationId, projectId, includeProcess, includeTeams, includeWorkItemTypes, includeFields, expandTeamIdentity }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = resolveProject(projectId);
        if (!proj) throw new Error("projectId is required");
        const result = await api.getProjectDetails(org, proj, {
          includeProcess,
          includeTeams,
          includeWorkItemTypes,
          includeFields,
          expandTeamIdentity,
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
