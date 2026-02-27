import { coreApi, projectApi } from "../client.js";
import type {
  AdoRepository,
  AdoRef,
  AdoTreeEntry,
  AdoCollectionResponse,
} from "../types.js";

export async function listRepositories(
  org: string,
  project?: string
): Promise<AdoRepository[]> {
  if (project) {
    const resp = await projectApi<AdoCollectionResponse<AdoRepository>>(
      org,
      project,
      "_apis/git/repositories"
    );
    return resp.value;
  }
  const resp = await coreApi<AdoCollectionResponse<AdoRepository>>(
    org,
    "_apis/git/repositories"
  );
  return resp.value;
}

export async function getRepository(
  org: string,
  repositoryId: string,
  project?: string
): Promise<AdoRepository> {
  if (project) {
    return projectApi<AdoRepository>(
      org,
      project,
      `_apis/git/repositories/${encodeURIComponent(repositoryId)}`
    );
  }
  return coreApi<AdoRepository>(
    org,
    `_apis/git/repositories/${encodeURIComponent(repositoryId)}`
  );
}

export async function getRepositoryDetails(
  org: string,
  repositoryId: string,
  project?: string,
  options?: {
    includeRefs?: boolean;
    includeStatistics?: boolean;
    branchName?: string;
    refFilter?: string;
  }
): Promise<{
  repository: AdoRepository;
  refs?: AdoRef[];
  statistics?: unknown;
}> {
  const repo = await getRepository(org, repositoryId, project);
  const result: { repository: AdoRepository; refs?: AdoRef[]; statistics?: unknown } = {
    repository: repo,
  };

  const projectScope = project || repo.project?.name;

  if (options?.includeRefs) {
    try {
      const resp = await projectApi<AdoCollectionResponse<AdoRef>>(
        org,
        projectScope,
        `_apis/git/repositories/${encodeURIComponent(repositoryId)}/refs`,
        {
          params: {
            filter: options?.refFilter,
          },
        }
      );
      result.refs = resp.value;
    } catch {
      // Refs are optional
    }
  }

  if (options?.includeStatistics && options?.branchName) {
    try {
      const stats = await projectApi<unknown>(
        org,
        projectScope,
        `_apis/git/repositories/${encodeURIComponent(repositoryId)}/stats/branches`,
        {
          params: { name: options.branchName },
        }
      );
      result.statistics = stats;
    } catch {
      // Stats are optional
    }
  }

  return result;
}

export async function getRepositoryTree(
  org: string,
  repositoryId: string,
  project: string,
  options?: {
    path?: string;
    depth?: number;
  }
): Promise<AdoTreeEntry[]> {
  // Get the default branch's tree
  const repo = await getRepository(org, repositoryId, project);
  const branch = repo.defaultBranch?.replace("refs/heads/", "") || "main";

  // Get items recursively
  const resp = await projectApi<AdoCollectionResponse<AdoTreeEntry>>(
    org,
    project,
    `_apis/git/repositories/${encodeURIComponent(repositoryId)}/items`,
    {
      params: {
        scopePath: options?.path || "/",
        recursionLevel: options?.depth === 1 ? "oneLevel" : "full",
        versionDescriptor_version: branch,
        versionDescriptor_versionType: "branch",
        "versionDescriptor.version": branch,
        "versionDescriptor.versionType": "branch",
      },
    }
  );
  return resp.value;
}

export async function getAllRepositoriesTree(
  org: string,
  project: string,
  options?: {
    depth?: number;
  }
): Promise<{ repository: string; items: AdoTreeEntry[] }[]> {
  const repos = await listRepositories(org, project);
  const results: { repository: string; items: AdoTreeEntry[] }[] = [];

  for (const repo of repos) {
    try {
      const items = await getRepositoryTree(org, repo.name, project, options);
      results.push({ repository: repo.name, items });
    } catch {
      results.push({ repository: repo.name, items: [] });
    }
  }

  return results;
}
