/** Shell-side reads of Host settings over the shared Web authentication and RPC APIs. */

import { randomUUID } from 'node:crypto'

/** Settings the Electron shell needs before the workspace renders. */
export interface DesktopHostSettings {
  /** @returns The saved UI language without provider requests. */
  readLocalePreference(): Promise<string | null>
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/**
 * Authenticate the native HTTP client through the Web application's launch URL.
 * @param authenticatedUrl - URL supplied by the running Desktop Host.
 * @param send - Electron session fetch, retaining the Web authentication cookie.
 * @returns settings reads over standard RPC.
 */
export async function connectDesktopHostSettings(
  authenticatedUrl: string,
  send: (input: string, init?: RequestInit) => Promise<Response>,
): Promise<DesktopHostSettings> {
  const origin = new URL(authenticatedUrl).origin
  const authenticated = await send(authenticatedUrl, { credentials: 'include' })
  await authenticated.body?.cancel()
  if (!authenticated.ok) throw new Error('desktop settings: Web authentication failed')
  const invoke = async (request: { namespace: string; method: string; args: Record<string, unknown> }): Promise<unknown> => {
    const rpcId = randomUUID()
    const method = `${request.namespace}/${request.method}`
    const response = await send(new URL(`/api/${method}`, origin).href, {
      method: 'POST', credentials: 'include', redirect: 'error',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId, method, payload: { args: request.args } }),
    })
    if (!response.ok) throw new Error('desktop settings: Web request failed')
    const envelope: unknown = await response.json()
    if (!record(envelope) || envelope.type !== 'server-response' || envelope.rpcId !== rpcId
      || !record(envelope.result) || envelope.result.ok !== true) {
      throw new Error('desktop settings: Web RPC failed')
    }
    return envelope.result.value
  }
  return {
    async readLocalePreference() {
      const settings = await invoke({ namespace: 'settings', method: 'describe', args: {} })
      if (!record(settings) || !Array.isArray(settings.namespaces)) throw new Error('desktop settings: missing settings namespaces')
      const locale: unknown = settings.namespaces.find((item: unknown) => record(item) && item.ns === 'locale')
      if (!record(locale) || !record(locale.value)
        || (locale.value.preference !== undefined && typeof locale.value.preference !== 'string')) {
        throw new Error('desktop settings: invalid locale preference')
      }
      return locale.value.preference ?? null
    },
  }
}
