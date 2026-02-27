import { coreApi, vsspsApi } from "../client.js";
import { loadConfig } from "../config.js";
export async function getMe() {
    const config = loadConfig();
    const data = await coreApi(config.organization, "_apis/connectiondata", { apiVersion: "7.1-preview.1" });
    const user = data.authenticatedUser;
    const email = user.properties?.["Account"]?.["$value"] || "";
    return {
        id: user.id,
        displayName: user.providerDisplayName,
        emailAddress: email,
        publicAlias: user.id,
    };
}
export async function listOrganizations() {
    const config = loadConfig();
    const me = await getMe();
    // Use VSSPS accounts API
    const resp = await vsspsApi(config.organization, "_apis/accounts", {
        params: { memberId: me.id },
        apiVersion: "7.1-preview.1",
    });
    return resp.value;
}
