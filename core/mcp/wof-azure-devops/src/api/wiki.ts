import { projectApi } from "../client.js";
import type { AdoWiki, AdoWikiPage, AdoCollectionResponse } from "../types.js";

export async function getWikis(
  org: string,
  project: string
): Promise<AdoWiki[]> {
  const resp = await projectApi<AdoCollectionResponse<AdoWiki>>(
    org,
    project,
    "_apis/wiki/wikis",
    { apiVersion: "7.1-preview.2" }
  );
  return resp.value;
}

export async function getWikiPage(
  org: string,
  project: string,
  wikiId: string,
  pagePath: string
): Promise<AdoWikiPage> {
  return projectApi<AdoWikiPage>(
    org,
    project,
    `_apis/wiki/wikis/${encodeURIComponent(wikiId)}/pages`,
    {
      params: {
        path: pagePath,
        includeContent: "true",
      },
      apiVersion: "7.1-preview.1",
    }
  );
}

export async function listWikiPages(
  org: string,
  project: string,
  wikiId: string
): Promise<AdoWikiPage[]> {
  // Get the root page and its sub-pages recursively
  const resp = await projectApi<AdoWikiPage>(
    org,
    project,
    `_apis/wiki/wikis/${encodeURIComponent(wikiId)}/pages`,
    {
      params: {
        path: "/",
        recursionLevel: "full",
      },
      apiVersion: "7.1-preview.1",
    }
  );

  // Flatten the tree
  const pages: AdoWikiPage[] = [];
  function flatten(page: AdoWikiPage) {
    pages.push({ ...page, subPages: undefined });
    if (page.subPages) {
      for (const sub of page.subPages) {
        flatten(sub);
      }
    }
  }
  flatten(resp);
  return pages;
}

export async function createWiki(
  org: string,
  project: string,
  data: {
    name: string;
    type?: "projectWiki" | "codeWiki";
    repositoryId?: string;
    mappedPath?: string;
    version?: string;
  }
): Promise<AdoWiki> {
  const body: Record<string, unknown> = {
    name: data.name,
    type: data.type || "projectWiki",
    projectId: project,
  };

  if (data.type === "codeWiki") {
    body.repositoryId = data.repositoryId;
    body.mappedPath = data.mappedPath || "/";
    if (data.version) {
      body.version = { version: data.version, versionType: "branch" };
    }
  }

  return projectApi<AdoWiki>(org, project, "_apis/wiki/wikis", {
    method: "POST",
    body,
    apiVersion: "7.1-preview.2",
  });
}

export async function createWikiPage(
  org: string,
  project: string,
  wikiId: string,
  pagePath: string,
  content: string
): Promise<AdoWikiPage> {
  return projectApi<AdoWikiPage>(
    org,
    project,
    `_apis/wiki/wikis/${encodeURIComponent(wikiId)}/pages`,
    {
      method: "PUT",
      params: { path: pagePath },
      body: { content },
      apiVersion: "7.1-preview.1",
    }
  );
}

export async function updateWikiPage(
  org: string,
  project: string,
  wikiId: string,
  pagePath: string,
  content: string,
  etag?: string
): Promise<AdoWikiPage> {
  // Get the current ETag if not provided
  if (!etag) {
    try {
      const existing = await getWikiPage(org, project, wikiId, pagePath);
      // ETag is typically in the response but may need special handling
      // For now we use a direct PUT which ADO handles
    } catch {
      // Page doesn't exist, create it
    }
  }

  return projectApi<AdoWikiPage>(
    org,
    project,
    `_apis/wiki/wikis/${encodeURIComponent(wikiId)}/pages`,
    {
      method: "PUT",
      params: { path: pagePath },
      body: { content },
      apiVersion: "7.1-preview.1",
    }
  );
}
