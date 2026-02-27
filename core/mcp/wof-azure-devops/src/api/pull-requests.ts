import { projectApi } from "../client.js";
import type {
  AdoPullRequest,
  AdoPullRequestThread,
  AdoPullRequestChange,
  AdoPolicyEvaluation,
  AdoCollectionResponse,
} from "../types.js";

function repoPath(repositoryId: string): string {
  return `_apis/git/repositories/${encodeURIComponent(repositoryId)}`;
}

export async function listPullRequests(
  org: string,
  project: string,
  repositoryId: string,
  options?: {
    status?: string;
    creatorId?: string;
    reviewerId?: string;
    sourceRefName?: string;
    targetRefName?: string;
    top?: number;
    skip?: number;
  }
): Promise<AdoPullRequest[]> {
  const resp = await projectApi<AdoCollectionResponse<AdoPullRequest>>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests`,
    {
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
    }
  );
  return resp.value;
}

export async function getPullRequest(
  org: string,
  project: string,
  repositoryId: string,
  pullRequestId: number
): Promise<AdoPullRequest> {
  return projectApi<AdoPullRequest>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests/${pullRequestId}`
  );
}

export async function createPullRequest(
  org: string,
  project: string,
  repositoryId: string,
  data: {
    title: string;
    description?: string;
    sourceRefName: string;
    targetRefName: string;
    reviewers?: string[];
    isDraft?: boolean;
    workItemRefs?: number[];
    labels?: string[];
  }
): Promise<AdoPullRequest> {
  const body: Record<string, unknown> = {
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

  return projectApi<AdoPullRequest>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests`,
    {
      method: "POST",
      body,
    }
  );
}

export async function updatePullRequest(
  org: string,
  project: string,
  repositoryId: string,
  pullRequestId: number,
  updates: {
    title?: string;
    description?: string;
    status?: string;
    targetRefName?: string;
    isDraft?: boolean;
    autoCompleteSetBy?: { id: string };
    completionOptions?: Record<string, unknown>;
  }
): Promise<AdoPullRequest> {
  return projectApi<AdoPullRequest>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests/${pullRequestId}`,
    {
      method: "PATCH",
      body: updates,
    }
  );
}

export async function getPullRequestComments(
  org: string,
  project: string,
  repositoryId: string,
  pullRequestId: number
): Promise<AdoPullRequestThread[]> {
  const resp = await projectApi<AdoCollectionResponse<AdoPullRequestThread>>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/threads`
  );
  return resp.value;
}

export async function addPullRequestComment(
  org: string,
  project: string,
  repositoryId: string,
  pullRequestId: number,
  content: string,
  options?: {
    threadId?: number;
    parentCommentId?: number;
    filePath?: string;
    lineNumber?: number;
    status?: string;
  }
): Promise<AdoPullRequestThread> {
  if (options?.threadId) {
    // Reply to existing thread
    return projectApi<AdoPullRequestThread>(
      org,
      project,
      `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/threads/${options.threadId}/comments`,
      {
        method: "POST",
        body: {
          content,
          parentCommentId: options.parentCommentId || 1,
          commentType: 1,
        },
      }
    );
  }

  // Create new thread
  const body: Record<string, unknown> = {
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

  return projectApi<AdoPullRequestThread>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/threads`,
    {
      method: "POST",
      body,
    }
  );
}

export async function getPullRequestChanges(
  org: string,
  project: string,
  repositoryId: string,
  pullRequestId: number
): Promise<AdoPullRequestChange[]> {
  const resp = await projectApi<{ changeEntries: AdoPullRequestChange[] }>(
    org,
    project,
    `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/iterations`,
    {}
  );

  // Get changes from the latest iteration
  if (!resp.changeEntries) {
    // Try via iterations approach
    const iterations = await projectApi<AdoCollectionResponse<{ id: number }>>(
      org,
      project,
      `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/iterations`
    );

    if (iterations.value.length === 0) return [];

    const latestId = iterations.value[iterations.value.length - 1].id;
    const changes = await projectApi<{
      changeEntries: AdoPullRequestChange[];
    }>(
      org,
      project,
      `${repoPath(repositoryId)}/pullrequests/${pullRequestId}/iterations/${latestId}/changes`
    );
    return changes.changeEntries || [];
  }

  return resp.changeEntries;
}

export async function getPullRequestChecks(
  org: string,
  project: string,
  repositoryId: string,
  pullRequestId: number
): Promise<AdoPolicyEvaluation[]> {
  // Get policy evaluations for the PR
  const artifactId = `vstfs:///CodeReview/CodeReviewId/${encodeURIComponent(project)}/${pullRequestId}`;
  const resp = await projectApi<AdoCollectionResponse<AdoPolicyEvaluation>>(
    org,
    project,
    `_apis/policy/evaluations`,
    {
      params: { artifactId },
      apiVersion: "7.1-preview.1",
    }
  );
  return resp.value;
}
