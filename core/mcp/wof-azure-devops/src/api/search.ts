import { searchApi, searchOrgApi } from "../client.js";
import type {
  AdoSearchResult,
  AdoCodeSearchResult,
  AdoWikiSearchResult,
  AdoWorkItemSearchResult,
} from "../types.js";

export async function searchCode(
  org: string,
  project: string,
  searchText: string,
  options?: {
    top?: number;
    skip?: number;
    includeSnippet?: boolean;
    includeContent?: boolean;
    filters?: {
      Repository?: string[];
      Path?: string[];
      Branch?: string[];
      CodeElement?: string[];
    };
  }
): Promise<AdoSearchResult<AdoCodeSearchResult>> {
  const body: Record<string, unknown> = {
    searchText,
    $top: options?.top || 100,
    $skip: options?.skip || 0,
    includeFacets: true,
    includeSnippet: options?.includeSnippet !== false,
  };

  if (options?.filters) {
    body.filters = options.filters;
  }

  const result = await searchApi<AdoSearchResult<AdoCodeSearchResult>>(
    org,
    project,
    "_apis/search/codesearchresults",
    {
      method: "POST",
      body,
      apiVersion: "7.1-preview.1",
    }
  );

  // Optionally fetch full file content
  if (options?.includeContent !== false && result.results) {
    // Content is included in the search results already for code search
  }

  return result;
}

export async function searchWiki(
  org: string,
  project: string | undefined,
  searchText: string,
  options?: {
    top?: number;
    skip?: number;
    includeFacets?: boolean;
    filters?: {
      Project?: string[];
    };
  }
): Promise<AdoSearchResult<AdoWikiSearchResult>> {
  const body: Record<string, unknown> = {
    searchText,
    $top: options?.top || 100,
    $skip: options?.skip || 0,
    includeFacets: options?.includeFacets !== false,
  };

  if (options?.filters) {
    body.filters = options.filters;
  }

  if (project) {
    return searchApi<AdoSearchResult<AdoWikiSearchResult>>(
      org,
      project,
      "_apis/search/wikisearchresults",
      {
        method: "POST",
        body,
        apiVersion: "7.1-preview.1",
      }
    );
  }

  return searchOrgApi<AdoSearchResult<AdoWikiSearchResult>>(
    org,
    "_apis/search/wikisearchresults",
    {
      method: "POST",
      body,
      apiVersion: "7.1-preview.1",
    }
  );
}

export async function searchWorkItems(
  org: string,
  project: string | undefined,
  searchText: string,
  options?: {
    top?: number;
    skip?: number;
    includeFacets?: boolean;
    orderBy?: { field: string; sortOrder: "ASC" | "DESC" }[];
    filters?: {
      "System.TeamProject"?: string[];
      "System.WorkItemType"?: string[];
      "System.State"?: string[];
      "System.AssignedTo"?: string[];
      "System.AreaPath"?: string[];
    };
  }
): Promise<AdoSearchResult<AdoWorkItemSearchResult>> {
  const body: Record<string, unknown> = {
    searchText,
    $top: options?.top || 100,
    $skip: options?.skip || 0,
    includeFacets: options?.includeFacets !== false,
  };

  if (options?.orderBy) {
    body.$orderBy = options.orderBy;
  }

  if (options?.filters) {
    body.filters = options.filters;
  }

  if (project) {
    return searchApi<AdoSearchResult<AdoWorkItemSearchResult>>(
      org,
      project,
      "_apis/search/workitemsearchresults",
      {
        method: "POST",
        body,
        apiVersion: "7.1-preview.1",
      }
    );
  }

  return searchOrgApi<AdoSearchResult<AdoWorkItemSearchResult>>(
    org,
    "_apis/search/workitemsearchresults",
    {
      method: "POST",
      body,
      apiVersion: "7.1-preview.1",
    }
  );
}
