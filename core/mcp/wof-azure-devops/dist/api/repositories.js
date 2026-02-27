import { coreApi, projectApi } from "../client.js";
export async function listRepositories(org, project) {
    if (project) {
        const resp = await projectApi(org, project, "_apis/git/repositories");
        return resp.value;
    }
    const resp = await coreApi(org, "_apis/git/repositories");
    return resp.value;
}
export async function getRepository(org, repositoryId, project) {
    if (project) {
        return projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}`);
    }
    return coreApi(org, `_apis/git/repositories/${encodeURIComponent(repositoryId)}`);
}
export async function getRepositoryDetails(org, repositoryId, project, options) {
    const repo = await getRepository(org, repositoryId, project);
    const result = {
        repository: repo,
    };
    const projectScope = project || repo.project?.name;
    if (options?.includeRefs) {
        try {
            const resp = await projectApi(org, projectScope, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/refs`, {
                params: {
                    filter: options?.refFilter,
                },
            });
            result.refs = resp.value;
        }
        catch {
            // Refs are optional
        }
    }
    if (options?.includeStatistics && options?.branchName) {
        try {
            const stats = await projectApi(org, projectScope, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/stats/branches`, {
                params: { name: options.branchName },
            });
            result.statistics = stats;
        }
        catch {
            // Stats are optional
        }
    }
    return result;
}
export async function getRepositoryTree(org, repositoryId, project, options) {
    // Get the default branch's tree
    const repo = await getRepository(org, repositoryId, project);
    const branch = repo.defaultBranch?.replace("refs/heads/", "") || "main";
    // Get items recursively
    const resp = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/items`, {
        params: {
            scopePath: options?.path || "/",
            recursionLevel: options?.depth === 1 ? "oneLevel" : "full",
            versionDescriptor_version: branch,
            versionDescriptor_versionType: "branch",
            "versionDescriptor.version": branch,
            "versionDescriptor.versionType": "branch",
        },
    });
    return resp.value;
}
export async function getAllRepositoriesTree(org, project, options) {
    const repos = await listRepositories(org, project);
    const results = [];
    for (const repo of repos) {
        try {
            const items = await getRepositoryTree(org, repo.name, project, options);
            results.push({ repository: repo.name, items });
        }
        catch {
            results.push({ repository: repo.name, items: [] });
        }
    }
    return results;
}
