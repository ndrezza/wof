import { projectApi } from "../client.js";
export async function getFileContent(org, project, repositoryId, options) {
    const params = {
        path: options?.path || "/",
        includeContent: "true",
    };
    if (options?.version) {
        params["versionDescriptor.version"] = options.version;
        params["versionDescriptor.versionType"] = options.versionType || "branch";
    }
    return projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/items`, {
        params,
        // Request raw text for files
    });
}
export async function createBranch(org, project, repositoryId, sourceBranch, newBranch) {
    // Get the source branch's latest commit
    const refs = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/refs`, {
        params: { filter: `heads/${sourceBranch}` },
    });
    if (!refs.value.length) {
        throw new Error(`Source branch '${sourceBranch}' not found`);
    }
    const sourceObjectId = refs.value[0].objectId;
    const zeroId = "0000000000000000000000000000000000000000";
    const resp = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/refs`, {
        method: "POST",
        body: [
            {
                name: `refs/heads/${newBranch}`,
                oldObjectId: zeroId,
                newObjectId: sourceObjectId,
            },
        ],
    });
    return resp.value[0];
}
export async function createCommit(org, project, repositoryId, branchName, commitMessage, changes) {
    // Get the latest commit on the branch
    const refs = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/refs`, {
        params: { filter: `heads/${branchName}` },
    });
    if (!refs.value.length) {
        throw new Error(`Branch '${branchName}' not found`);
    }
    const oldObjectId = refs.value[0].objectId;
    const body = {
        refUpdates: [
            {
                name: `refs/heads/${branchName}`,
                oldObjectId,
            },
        ],
        commits: [
            {
                comment: commitMessage,
                changes: changes.map((c) => ({
                    changeType: c.changeType === "add" ? 1 : c.changeType === "edit" ? 2 : 16,
                    item: { path: c.path },
                    newContent: c.content !== undefined
                        ? {
                            content: c.content,
                            contentType: c.contentType === "base64" ? 1 : 0,
                        }
                        : undefined,
                })),
            },
        ],
    };
    const resp = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/pushes`, {
        method: "POST",
        body,
    });
    return resp.commits[0];
}
export async function listCommits(org, project, repositoryId, branchName, options) {
    const resp = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/commits`, {
        params: {
            "searchCriteria.itemVersion.version": branchName,
            "searchCriteria.itemVersion.versionType": "branch",
            "$top": options?.top || 10,
            "$skip": options?.skip,
        },
    });
    // Fetch changes for each commit
    const commits = [];
    for (const commit of resp.value) {
        try {
            const detail = await projectApi(org, project, `_apis/git/repositories/${encodeURIComponent(repositoryId)}/commits/${commit.commitId}/changes`);
            commits.push({ ...commit, changes: detail.changes });
        }
        catch {
            commits.push(commit);
        }
    }
    return commits;
}
