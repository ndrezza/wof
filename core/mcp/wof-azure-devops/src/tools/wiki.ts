import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/wiki.js";
import { resolveOrg, requireProject } from "../config.js";

export function registerWikiTools(server: McpServer) {
  server.tool(
    "get_wikis",
    "List all wikis in a project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
    },
    async ({ organizationId, projectId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const wikis = await api.getWikis(org, proj);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(wikis, null, 2) }],
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
    "get_wiki_page",
    "Get the content of a wiki page",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      wikiId: z.string().describe("The ID or name of the wiki"),
      pagePath: z.string().describe("The path of the page within the wiki"),
    },
    async ({ organizationId, projectId, wikiId, pagePath }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const page = await api.getWikiPage(org, proj, wikiId, pagePath);
        return {
          content: [{ type: "text" as const, text: page.content || JSON.stringify(page, null, 2) }],
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
    "list_wiki_pages",
    "List pages within an Azure DevOps wiki",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      wikiId: z.string().describe("The ID or name of the wiki"),
    },
    async ({ organizationId, projectId, wikiId }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const pages = await api.listWikiPages(org, proj, wikiId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(pages, null, 2) }],
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
    "create_wiki",
    "Create a new wiki in a project",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      name: z.string().describe("The name of the wiki"),
      type: z.enum(["projectWiki", "codeWiki"]).default("projectWiki").optional().describe("Type of wiki"),
      repositoryId: z.string().optional().describe("Repository ID (required for code wikis)"),
      mappedPath: z.string().optional().describe("Mapped path in the repository (for code wikis)"),
      version: z.string().optional().describe("Branch name (for code wikis)"),
    },
    async ({ organizationId, projectId, name, type, repositoryId, mappedPath, version }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const wiki = await api.createWiki(org, proj, { name, type, repositoryId, mappedPath, version });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(wiki, null, 2) }],
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
    "create_wiki_page",
    "Create a new page in a wiki",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      wikiId: z.string().describe("The ID or name of the wiki"),
      pagePath: z.string().describe("The path for the new page"),
      content: z.string().describe("The page content (markdown)"),
    },
    async ({ organizationId, projectId, wikiId, pagePath, content }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const page = await api.createWikiPage(org, proj, wikiId, pagePath, content);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(page, null, 2) }],
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
    "update_wiki_page",
    "Update the content of an existing wiki page",
    {
      organizationId: z.string().optional().describe("The ID or name of the organization"),
      projectId: z.string().optional().describe("The ID or name of the project"),
      wikiId: z.string().describe("The ID or name of the wiki"),
      pagePath: z.string().describe("The path of the page to update"),
      content: z.string().describe("The updated page content (markdown)"),
    },
    async ({ organizationId, projectId, wikiId, pagePath, content }) => {
      try {
        const org = resolveOrg(organizationId);
        const proj = requireProject(projectId);
        const page = await api.updateWikiPage(org, proj, wikiId, pagePath, content);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(page, null, 2) }],
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
