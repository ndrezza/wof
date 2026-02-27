import { projectApi } from "../client.js";
function repoPath(repositoryId) {
    return `_apis/git/repositories/${encodeURIComponent(repositoryId)}`;
}
export async function listPullRequests(org, project, repositoryId, options) {
    const resp = await projectApi(org, project, `${repoPath(repositoryId)}/pullrequests`, {
        params: {
            "searchCriteria.status": options?.status || "active",
            "searchCriteria.creatorId": options?.creatorId,
            "searchCriteria.reviewerId": options?.reviewerId,
            "searchCriteria.sourceRefName": options?.sourceRefName
                ? `refs/heads/${options.sourceRefName}`
                : undefined,
            "searchCriteria.targetRefName": options?.targetRefName
                ? `refs/heads/${options.targetRefName}`
                : undefined,
            $top: options?.top || 10,
            $skip: options?.skip,
        },
    });
    return resp.value;
}
export async function getPullRequest(org, project, repositoryId, pullRequestId) {
    return projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}`);
}
export async function createPullRequest(org, project, repositoryId, data) {
    const body = {
        title: data.title,
        description: data.description,
        sourceRefName: data.sourceRefName.startsWith("refs/")
            ? data.sourceRefName
            : `refs/heads/${data.sourceRefName}`,
        targetRefName: data.targetRefName.startsWith("refs/")
            ? data.targetRefName
            : `refs/heads/${data.targetRefName}`,
        isDraft: data.isDraft || false,
    };
    if (data.reviewers?.length) {
        body.reviewers = data.reviewers.map((r) => ({ id: r }));
    }
    if (data.workItemRefs?.length) {
        body.workItemRefs = data.workItemRefs.map((id) => ({ id: String(id) }));
    }
    if (data.labels?.length) {
        body.labels = data.labels.map((name) => ({ name }));
    }
    return projectApi(org, project, `${repoPath(repositoryId)}/pullrequests`, {
        method: "POST",
        body,
    });
}
export async function updatePullRequest(org, project, repositoryId, pullRequestId, updates) {
    return projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}`, {
        method: "PATCH",
        body: updates,
    });
}
export async function getPullRequestComments(org, project, repositoryId, pullRequestId) {
    const resp = await projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/threads`);
    return resp.value;
}
export async function addPullRequestComment(org, project, repositoryId, pullRequestId, content, options) {
    if (options?.threadId) {
        // Reply to existing thread
        return projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/threads/${options.threadId}/comments`, {
            method: "POST",
            body: {
                content,
                parentCommentId: options.parentCommentId || 1,
                commentType: 1,
            },
        });
    }
    // Create new thread
    const body = {
        comments: [{ content, commentType: 1 }],
        status: options?.status === "closed" ? 2 : 1,
    };
    if (options?.filePath) {
        body.threadContext = {
            filePath: options.filePath,
            rightFileStart: options?.lineNumber
                ? { line: options.lineNumber, offset: 1 }
                : undefined,
            rightFileEnd: options?.lineNumber
                ? { line: options.lineNumber, offset: 1 }
                : undefined,
        };
    }
    return projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/threads`, {
        method: "POST",
        body,
    });
}
export async function getPullRequestChanges(org, project, repositoryId, pullRequestId) {
    const resp = await projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/iterations`, {});
    // Get changes from the latest iteration
    if (!resp.changeEntries) {
        // Try via iterations approach
        const iterations = await projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/iterations`);
        if (iterations.value.length === 0)
            return [];
        const latestId = iterations.value[iterations.value.length - 1].id;
        const changes = await projectApi(org, project, `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/iterations/${latestId}/changes`);
        return changes.changeEntries || [];
    }
    return resp.changeEntries;
}
export async function getPullRequestChecks(org, project, repositoryId, pullRequestId) {
    // Get policy evaluations for the PR
    const artifactId = `vstfs:///CodeReview/CodeReviewId/${encodeURIComponent(project)}/${pullRequestId}`;
    const resp = await projectApi(org, project, `_apis/policy/evaluations`, {
        params: { artifactId },
        apiVersion: "7.1-preview.1",
    });
    return resp.value;
}
