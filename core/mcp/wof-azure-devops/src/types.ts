// Azure DevOps MCP server configuration
export interface AdoConfig {
  organization: string;
  pat: string;
  defaultProject?: string;
}

// Base URL hosts
export const ADO_CORE_HOST = "dev.azure.com";
export const ADO_VSSPS_HOST = "vssps.dev.azure.com";
export const ADO_VSSPS_APP_HOST = "app.vssps.visualstudio.com";
export const ADO_SEARCH_HOST = "almsearch.dev.azure.com";

// API responses
export interface AdoCollectionResponse<T> {
  count: number;
  value: T[];
}

export interface AdoPaginatedResponse<T> extends AdoCollectionResponse<T> {
  continuationToken?: string;
}

// Identity
export interface AdoProfile {
  id: string;
  displayName: string;
  emailAddress: string;
  publicAlias: string;
}

export interface AdoAccount {
  accountId: string;
  accountName: string;
  accountUri: string;
}

// Projects
export interface AdoProject {
  id: string;
  name: string;
  description?: string;
  url: string;
  state: string;
  visibility: string;
}

export interface AdoTeam {
  id: string;
  name: string;
  description?: string;
}

export interface AdoProcess {
  id: string;
  name: string;
  description?: string;
}

// Repositories
export interface AdoRepository {
  id: string;
  name: string;
  url: string;
  defaultBranch?: string;
  size: number;
  project: { id: string; name: string };
}

export interface AdoTreeEntry {
  objectId: string;
  relativePath: string;
  mode: string;
  gitObjectType: string;
  size?: number;
  url: string;
}

export interface AdoRef {
  name: string;
  objectId: string;
}

// Git
export interface AdoCommit {
  commitId: string;
  author: { name: string; email: string; date: string };
  committer: { name: string; email: string; date: string };
  comment: string;
  url: string;
  changeCounts?: { Add: number; Edit: number; Delete: number };
  changes?: AdoChange[];
}

export interface AdoChange {
  item: { path: string; objectId?: string };
  changeType: string;
  newContent?: { content: string; contentType: string };
}

export interface AdoGitRefUpdate {
  name: string;
  oldObjectId: string;
  newObjectId: string;
}

// Work Items
export interface AdoWorkItem {
  id: number;
  rev: number;
  fields: Record<string, unknown>;
  url: string;
  relations?: AdoWorkItemRelation[];
}

export interface AdoWorkItemRelation {
  rel: string;
  url: string;
  attributes: Record<string, unknown>;
}

export interface AdoWorkItemType {
  name: string;
  description?: string;
  states?: { name: string; color: string; category: string }[];
  fields?: { name: string; referenceName: string; type: string }[];
}

// Pull Requests
export interface AdoPullRequest {
  pullRequestId: number;
  title: string;
  description?: string;
  status: string;
  createdBy: { displayName: string; uniqueName: string; id: string };
  creationDate: string;
  sourceRefName: string;
  targetRefName: string;
  mergeStatus?: string;
  isDraft: boolean;
  reviewers?: AdoReviewer[];
  labels?: { name: string }[];
  url: string;
  repository: { id: string; name: string };
}

export interface AdoReviewer {
  id: string;
  displayName: string;
  uniqueName: string;
  vote: number;
  isRequired?: boolean;
}

export interface AdoPullRequestThread {
  id: number;
  status: string;
  comments: AdoPullRequestComment[];
  threadContext?: {
    filePath?: string;
    rightFileStart?: { line: number; offset: number };
    rightFileEnd?: { line: number; offset: number };
  };
  properties?: Record<string, unknown>;
  publishedDate: string;
  lastUpdatedDate: string;
}

export interface AdoPullRequestComment {
  id: number;
  parentCommentId?: number;
  content: string;
  author: { displayName: string; uniqueName: string };
  publishedDate: string;
  commentType: string;
}

export interface AdoPullRequestChange {
  changeId: number;
  item: { path: string; objectId?: string };
  changeType: string;
}

export interface AdoPolicyEvaluation {
  evaluationId: string;
  status: string;
  configuration: {
    type: { displayName: string };
    settings?: Record<string, unknown>;
  };
  context?: Record<string, unknown>;
}

// Pipelines
export interface AdoPipeline {
  id: number;
  name: string;
  folder: string;
  revision: number;
  url: string;
  configuration?: {
    type: string;
    path?: string;
    repository?: { id: string; name: string; type: string };
  };
}

export interface AdoPipelineRun {
  id: number;
  name: string;
  state: string;
  result?: string;
  createdDate: string;
  finishedDate?: string;
  pipeline: { id: number; name: string };
  resources?: Record<string, unknown>;
  templateParameters?: Record<string, string>;
  url: string;
}

export interface AdoTimelineRecord {
  id: string;
  parentId?: string;
  type: string;
  name: string;
  state: string;
  result?: string;
  startTime?: string;
  finishTime?: string;
  order: number;
  log?: { id: number; url: string };
  issues?: { type: string; message: string; category: string }[];
  errorCount: number;
  warningCount: number;
}

export interface AdoBuildLog {
  id: number;
  lineCount: number;
  createdOn: string;
  url: string;
}

// Wiki
export interface AdoWiki {
  id: string;
  name: string;
  type: string;
  url: string;
  projectId?: string;
  repositoryId?: string;
  mappedPath?: string;
}

export interface AdoWikiPage {
  id: number;
  path: string;
  content?: string;
  gitItemPath?: string;
  subPages?: AdoWikiPage[];
  url: string;
  remoteUrl?: string;
}

// Search
export interface AdoSearchResult<T> {
  count: number;
  results: T[];
  infoCode?: number;
  facets?: Record<string, { name: string; id: string; resultCount: number }[]>;
}

export interface AdoCodeSearchResult {
  fileName: string;
  path: string;
  repository: { name: string; id: string };
  project: { name: string; id: string };
  versions?: { branchName: string }[];
  matches?: Record<string, { charOffset: number; length: number }[]>;
  contentId?: string;
  content?: string;
}

export interface AdoWikiSearchResult {
  wiki: { name: string; id: string };
  path: string;
  fileName: string;
  content?: string;
  hits?: { fieldReferenceName: string; highlights: string[] }[];
}

export interface AdoWorkItemSearchResult {
  fields: Record<string, string>;
  hits: { fieldReferenceName: string; highlights: string[] }[];
  project: { name: string; id: string };
  url: string;
}
