import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/identity.js";

export function registerIdentityTools(server: McpServer) {
  server.tool(
    "get_me",
    "Get details of the authenticated user (id, displayName, email)",
    {},
    async () => {
      try {
        const profile = await api.getMe();
        return {
          content: [{ type: "text" as const, text: JSON.stringify(profile, null, 2) }],
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
    "list_organizations",
    "List all Azure DevOps organizations accessible to the current authentication",
    {},
    async () => {
      try {
        const orgs = await api.listOrganizations();
        return {
          content: [{ type: "text" as const, text: JSON.stringify(orgs, null, 2) }],
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
