import { coreApi, projectApi } from "../client.js";
import type { AdoWorkItem, AdoCollectionResponse } from "../types.js";

export async function listWorkItems(
  org: string,
  project: string,
  options?: {
    ids?: number[];
    wiql?: string;
    top?: number;
    fields?: string[];
  }
): Promise<AdoWorkItem[]> {
  if (options?.ids && options.ids.length > 0) {
    // Get by IDs directly
    const resp = await coreApi<AdoCollectionResponse<AdoWorkItem>>(
      org,
      `_apis/wit/workitems`,
      {
        params: {
          ids: options.ids.join(","),
          $expand: "relations",
          fields: options.fields?.join(","),
        },
      }
    );
    return resp.value;
  }

  // Use WIQL query
  const wiql =
    options?.wiql ||
    `SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo] ` +
      `FROM WorkItems WHERE [System.TeamProject] = '${project}' ` +
      `AND [System.State] <> 'Removed' ORDER BY [System.ChangedDate] DESC`;

  const queryResult = await projectApi<{
    workItems: { id: number; url: string }[];
  }>(org, project, "_apis/wit/wiql", {
    method: "POST",
    body: { query: wiql },
    params: { $top: options?.top || 200 },
  });

  if (!queryResult.workItems.length) return [];

  // Fetch full work item details in batches of 200
  const allItems: AdoWorkItem[] = [];
  const ids = queryResult.workItems.map((wi) => wi.id);

  for (let i = 0; i < ids.length; i += 200) {
    const batch = ids.slice(i, i + 200);
    const resp = await coreApi<AdoCollectionResponse<AdoWorkItem>>(
      org,
      `_apis/wit/workitems`,
      {
        params: {
          ids: batch.join(","),
          $expand: "relations",
          fields: options?.fields?.join(","),
        },
      }
    );
    allItems.push(...resp.value);
  }

  return allItems;
}

export async function getWorkItem(
  org: string,
  workItemId: number,
  options?: {
    expand?: string;
    fields?: string[];
  }
): Promise<AdoWorkItem> {
  return coreApi<AdoWorkItem>(org, `_apis/wit/workitems/${workItemId}`, {
    params: {
      $expand: options?.expand || "relations",
      fields: options?.fields?.join(","),
    },
  });
}

export async function createWorkItem(
  org: string,
  project: string,
  workItemType: string,
  fields: Record<string, unknown>
): Promise<AdoWorkItem> {
  // Build JSON Patch document
  const patchDoc = Object.entries(fields).map(([key, value]) => ({
    op: "add",
    path: `/fields/${key}`,
    value,
  }));

  return projectApi<AdoWorkItem>(
    org,
    project,
    `_apis/wit/workitems/$${encodeURIComponent(workItemType)}`,
    {
      method: "POST",
      body: patchDoc,
      contentType: "application/json-patch+json",
    }
  );
}

export async function updateWorkItem(
  org: string,
  workItemId: number,
  fields: Record<string, unknown>
): Promise<AdoWorkItem> {
  const patchDoc = Object.entries(fields).map(([key, value]) => ({
    op: value === null ? "remove" : "replace",
    path: `/fields/${key}`,
    value,
  }));

  return coreApi<AdoWorkItem>(org, `_apis/wit/workitems/${workItemId}`, {
    method: "PATCH",
    body: patchDoc,
    contentType: "application/json-patch+json",
  });
}

export async function manageWorkItemLink(
  org: string,
  workItemId: number,
  operation: "add" | "remove",
  targetId: number,
  linkType: string,
  comment?: string
): Promise<AdoWorkItem> {
  const targetUrl = `https://dev.azure.com/${org}/_apis/wit/workitems/${targetId}`;

  const patchDoc =
    operation === "add"
      ? [
          {
            op: "add",
            path: "/relations/-",
            value: {
              rel: linkType,
              url: targetUrl,
              attributes: comment ? { comment } : {},
            },
          },
        ]
      : [
          {
            op: "test",
            path: "/relations/0/url", // Will need index resolution
            value: targetUrl,
          },
          {
            op: "remove",
            path: "/relations/0",
          },
        ];

  // For remove, we need to find the correct relation index
  if (operation === "remove") {
    const wi = await getWorkItem(org, workItemId);
    const relIndex = wi.relations?.findIndex(
      (r) => r.rel === linkType && r.url.includes(`/${targetId}`)
    );
    if (relIndex === undefined || relIndex < 0) {
      throw new Error(
        `No '${linkType}' relation to work item ${targetId} found`
      );
    }
    return coreApi<AdoWorkItem>(org, `_apis/wit/workitems/${workItemId}`, {
      method: "PATCH",
      body: [{ op: "remove", path: `/relations/${relIndex}` }],
      contentType: "application/json-patch+json",
    });
  }

  return coreApi<AdoWorkItem>(org, `_apis/wit/workitems/${workItemId}`, {
    method: "PATCH",
    body: patchDoc,
    contentType: "application/json-patch+json",
  });
}
