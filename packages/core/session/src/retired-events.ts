/**
 * Session events whose writers were removed from this distribution. They stay declared so
 * existing format-4 logs that contain them remain readable; no plugin appends them.
 * @module @deepseek-ai/dsh-session/retired-events
 */

export {}

declare module '@deepseek-ai/dsh-session/types' {
  interface SessionEventMap {
    /** Retired DeepSeek session-log upload watermark through `throughSeq`. */
    'session-log-deepseek/delivery-accepted': {
      /** Session identity the accepted delivery carried; inherited fork markers retain the parent's id. */
      sessionId: import('@deepseek-ai/dsh-session/types').SessionId
      /** Accepted Session format generation; absence identifies version 0. */
      sessionFormatVersion?: number
      /** Last canonical event included in the accepted request. */
      throughSeq: import('@deepseek-ai/dsh-session/types').SessionSeq
    }
    /** Retired secret-free DeepSeek native search request recorded before dispatch. */
    'web/deepseek-search-llm-request': {
      /** Fully resolved Messages endpoint. */
      readonly endpoint: string
      /** `anthropic-version` header value. */
      readonly apiVersion: string
      /** Exact JSON body sent to the provider. */
      readonly body: {
        readonly model: string
        readonly max_tokens: number
        readonly messages: readonly [{
          readonly role: 'user'
          readonly content: readonly [{
            readonly type: 'text'
            readonly text: string
          }]
        }]
        readonly tools: readonly [{
          readonly type: 'web_search_20250305'
          readonly name: 'web_search'
          readonly max_uses: number
        }]
      }
    }
  }
}
