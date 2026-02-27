import { coreApi, vsspsApi } from "../client.js";
import { loadConfig } from "../config.js";
import type { AdoProfile, AdoAccount, AdoCollectionResponse } from "../types.js";

interface ConnectionData {
  authenticatedUser: {
    id: string;
    descriptor: string;
    subjectDescriptor: string;
    providerDisplayName: string;
    properties: Record<string, { $type: string; $value: string }>;
  };
  authorizedUser: {
    id: string;
    descriptor: string;
    subjectDescriptor: string;
    providerDisplayName: string;
    properties: Record<string, { $type: string; $value: string }>;
  };
}

export async function getMe(): Promise<AdoProfile> {
  const config = loadConfig();
  const data = await coreApi<ConnectionData>(
    config.organization,
    "_apis/connectiondata",
    { apiVersion: "7.1-preview.1" }
  );

  const user = data.authenticatedUser;
  const email =
    user.properties?.["Account"]?.["$value"] || "";

  return {
    id: user.id,
    displayName: user.providerDisplayName,
    emailAddress: email,
    publicAlias: user.id,
  };
}

export async function listOrganizations(): Promise<AdoAccount[]> {
  const config = loadConfig();
  const me = await getMe();

  // Use VSSPS accounts API
  const resp = await vsspsApi<AdoCollectionResponse<AdoAccount>>(
    config.organization,
    "_apis/accounts",
    {
      params: { memberId: me.id },
      apiVersion: "7.1-preview.1",
    }
  );
  return resp.value;
}
