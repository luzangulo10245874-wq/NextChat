// Stub for Tauri desktop build (static export mode).
// Server Actions ("use server") are not supported with output: "export",
// so MCP features are disabled in the desktop app.

export async function isMcpEnabled() {
  return false;
}

export async function getClientsStatus(_accessCode: string) {
  return {};
}

export async function getClientTools(_clientId: string, _accessCode: string) {
  return null;
}

export async function getAvailableClientsCount(_accessCode: string) {
  return 0;
}

export async function getAllTools(_accessCode: string) {
  return [];
}

export async function initializeMcpSystem(_accessCode: string) {
  return { mcpServers: {} };
}

export async function addMcpServer(
  _clientId: string,
  _config: any,
  _accessCode: string,
) {
  return { mcpServers: {} };
}

export async function pauseMcpServer(_clientId: string, _accessCode: string) {
  return { mcpServers: {} };
}

export async function resumeMcpServer(
  _clientId: string,
  _accessCode: string,
): Promise<void> {}

export async function removeMcpServer(_clientId: string, _accessCode: string) {
  return { mcpServers: {} };
}

export async function restartAllClients(_accessCode: string) {
  return { mcpServers: {} };
}

export async function executeMcpAction(
  _clientId: string,
  _request: any,
  _accessCode: string,
) {
  throw new Error("MCP not available in desktop mode");
}

export async function getMcpConfigFromFile(_accessCode: string) {
  return { mcpServers: {} };
}
