import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/work-items.js";
import { resolveOrg, requireProject } from "../config.js";

export function registerWorkItemTools(server: McpServer) {
  server.tool(
    "list_work_items",
    "List work items in a project using WIQL query or by IDs",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      ids: z.array(z.number()).optional().describe("Specific work item IDs to retrieve"),
      wiql: z.string().optional().describe("WIQL query to find work items"),
      top: z.number().optional().describe("Maximum number of work items to return"),
    },
    async ({ organizationId, projectId, ids, wiql, top }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const items = await api.listWorkItems(org, proj, { ids, wiql, top });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(items, null, 2) }],
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
    "get_work_item",
    "Get details of a specific work item",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      workItemId: z.number().describe("The ID of the work item"),
    },
    async ({ organizationId, workItemId }) => {
      try {
        const org = resolveOrg(organizationId);
        const item = await api.getWorkItem(org, workItemId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(item, null, 2) }],
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
    "create_work_item",
    "Create a new work item",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      workItemType: z.string().describe("The type of work item to create (e.g., 'Task', 'Bug', 'User Story')"),
      title: z.string().describe("The title of the work item"),
      description: z.string().optional().describe("Work item description in HTML format"),
      assignedTo: z.string().optional().describe("The email or name of the user to assign"),
      areaPath: z.string().optional().describe("The area path for the work item"),
      iterationPath: z.string().optional().describe("The iteration path for the work item"),
      priority: z.number().optional().describe("The priority of the work item"),
      parentId: z.number().optional().describe("The ID of the parent work item"),
      additionalFields: z.record(z.string(), z.unknown()).optional().describe("Additional fields to set. Multi-line text fields must use HTML format."),
    },
    async ({ organizationId, projectId, workItemType, title, description, assignedTo, areaPath, iterationPath, priority, parentId, additionalFields }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);

        const fields: Record<string, unknown> = {
          "System.Title": title,
        };
        if (description) fields["System.Description"] = description;
        if (assignedTo) fields["System.AssignedTo"] = assignedTo;
        if (areaPath) fields["System.AreaPath"] = areaPath;
        if (iterationPath) fields["System.IterationPath"] = iterationPath;
        if (priority) fields["Microsoft.VSTS.Common.Priority"] = priority;
        if (additionalFields) Object.assign(fields, additionalFields);

        const item = await api.createWorkItem(org, proj, workItemType, fields);

        // Add parent link if specified
        if (parentId) {
          await api.manageWorkItemLink(org, item.id, "add", parentId, "System.LinkTypes.Hierarchy-Reverse");
        }

        return {
          content: [{ type: "text" as const, text: JSON.stringify(item, null, 2) }],
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
    "update_work_item",
    "Update an existing work item",
    {
      workItemId: z.number().describe("The ID of the work item to update"),
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      title: z.string().optional().describe("The updated title"),
      description: z.string().optional().describe("Work item description in HTML format"),
      state: z.string().optional().describe("The updated state"),
      assignedTo: z.string().optional().describe("The email or name of the user to assign"),
      areaPath: z.string().optional().describe("The updated area path"),
      iterationPath: z.string().optional().describe("The updated iteration path"),
      priority: z.number().optional().describe("The updated priority"),
      additionalFields: z.record(z.string(), z.unknown()).optional().describe("Additional fields to update. Multi-line text fields must use HTML format."),
    },
    async ({ workItemId, organizationId, title, description, state, assignedTo, areaPath, iterationPath, priority, additionalFields }) => {
      try {
        const org = resolveOrg(organizationId);

        const fields: Record<string, unknown> = {};
        if (title) fields["System.Title"] = title;
        if (description) fields["System.Description"] = description;
        if (state) fields["System.State"] = state;
        if (assignedTo) fields["System.AssignedTo"] = assignedTo;
        if (areaPath) fields["System.AreaPath"] = areaPath;
        if (iterationPath) fields["System.IterationPath"] = iterationPath;
        if (priority) fields["Microsoft.VSTS.Common.Priority"] = priority;
        if (additionalFields) Object.assign(fields, additionalFields);

        const item = await api.updateWorkItem(org, workItemId, fields);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(item, null, 2) }],
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
    "manage_work_item_link",
    "Add or remove a link between two work items",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      workItemId: z.number().describe("The ID of the source work item"),
      operation: z.enum(["add", "remove"]).describe("Whether to add or remove the link"),
      targetId: z.number().describe("The ID of the target work item"),
      linkType: z.string().describe("The link type (e.g., 'System.LinkTypes.Hierarchy-Forward', 'System.LinkTypes.Related')"),
      comment: z.string().optional().describe("Optional comment for the link"),
    },
    async ({ organizationId, workItemId, operation, targetId, linkType, comment }) => {
      try {
        const org = resolveOrg(organizationId);
        const item = await api.manageWorkItemLink(org, workItemId, operation, targetId, linkType, comment);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(item, null, 2) }],
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
