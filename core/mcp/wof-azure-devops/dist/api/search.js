import { searchApi, searchOrgApi } from "../client.js";
export async function searchCode(org, project, searchText, options) {
    const body = {
        searchText,
        $top: options?.top || 100,
        $skip: options?.skip || 0,
        includeFacets: true,
        includeSnippet: options?.includeSnippet !== false,
    };
    if (options?.filters) {
        body.filters = options.filters;
    }
    const result = await searchApi(org, project, "_apis/search/codesearchresults", {
        method: "POST",
        body,
        apiVersion: "7.1-preview.1",
    });
    // Optionally fetch full file content
    if (options?.includeContent !== false && result.results) {
        // Content is included in the search results already for code search
    }
    return result;
}
export async function searchWiki(org, project, searchText, options) {
    const body = {
        searchText,
        $top: options?.top || 100,
        $skip: options?.skip || 0,
        includeFacets: options?.includeFacets !== false,
    };
    if (options?.filters) {
        body.filters = options.filters;
    }
    if (project) {
        return searchApi(org, project, "_apis/search/wikisearchresults", {
            method: "POST",
            body,
            apiVersion: "7.1-preview.1",
        });
    }
    return searchOrgApi(org, "_apis/search/wikisearchresults", {
        method: "POST",
        body,
        apiVersion: "7.1-preview.1",
    });
}
export async function searchWorkItems(org, project, searchText, options) {
    const body = {
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
        return searchApi(org, project, "_apis/search/workitemsearchresults", {
            method: "POST",
            body,
            apiVersion: "7.1-preview.1",
        });
    }
    return searchOrgApi(org, "_apis/search/workitemsearchresults", {
        method: "POST",
        body,
        apiVersion: "7.1-preview.1",
    });
}
