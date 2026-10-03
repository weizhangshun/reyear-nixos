// Keyless mock LLM adapter for evaluating the harness without a provider account.
// Scripted behaviour: asks to run `ls` when the prompt mentions files, otherwise echoes.
import { LlmAdapter, CallId } from '@deepseek-ai/dsh-llm'

const PROVIDER = 'mock'
const MODEL = 'mock-echo-1'

function textOf(message) {
  return (message?.content ?? []).filter(b => b.type === 'text').map(b => b.text).join('')
}

class MockAdapter extends LlmAdapter {
  providerInfo(provider) { return { id: provider, name: 'Mock (keyless)' } }
  async listModels(provider) {
    return [{ provider, id: MODEL, name: 'Mock Echo', description: 'Scripted offline model', inputModalities: ['text'] }]
  }
  async resolveModel(provider, model) {
    return { provider, id: model, name: 'Mock Echo', context: { contextWindow: 32000 } }
  }
  async *stream(options) {
    const messages = options.messages
    const last = messages[messages.length - 1]
    const toolResult = last?.content?.find(b => b.type === 'tool-result')
    const toolNames = (options.tools ?? []).map(t => t.name)
    let reply
    let toolCall

    if (toolResult) {
      const out = (toolResult.content ?? []).filter(b => b.type === 'text').map(b => b.text).join('').trim()
      reply = `The \`bash\` tool returned ${out.length} chars${toolResult.isError ? ' (error)' : ''}. First lines:\n\n` +
        out.split('\n').slice(0, 8).map(l => '    ' + l).join('\n')
    } else {
      const prompt = textOf(messages.filter(m => m.source?.kind === 'user').at(-1))
      if (process.env.MOCK_LLM_DEBUG) console.error('[mock-llm] system chars =', (options.system ?? '').length, 'tools json chars =', JSON.stringify(options.tools ?? []).length, 'history msgs =', messages.length)
      if (/\b(list|files|directory|ls)\b/i.test(prompt) && toolNames.includes('bash')) {
        reply = 'I will list the workspace directory.'
        toolCall = { id: CallId('mock-' + Date.now()), name: 'bash', arguments: JSON.stringify({ command: 'ls -la', description: 'List files in workspace' }) }
      } else {
        reply = `Mock model (no API key) here. You said: "${prompt}". ` +
          `I can see ${toolNames.length} tools: ${toolNames.slice(0, 6).join(', ')}${toolNames.length > 6 ? ', …' : ''}. ` +
          `Ask me to "list files" to watch a tool call go through the pipeline.`
      }
    }

    yield { type: 'block-start', index: 0, blockType: 'text' }
    for (const word of reply.split(/(?<= )/)) {
      yield { type: 'text-delta', index: 0, text: word }
      await new Promise(r => setTimeout(r, 15))
      if (options.signal?.aborted) return
    }
    yield { type: 'block-end', index: 0, block: { type: 'text', text: reply } }

    if (toolCall) {
      yield { type: 'block-start', index: 1, blockType: 'tool-call' }
      yield { type: 'tool-call-delta', index: 1, id: toolCall.id, name: toolCall.name, argumentsDelta: toolCall.arguments }
      yield { type: 'block-end', index: 1, block: { type: 'tool-call', ...toolCall } }
    }
    yield { type: 'usage', usage: { inputTokens: 42, outputTokens: reply.length / 4 | 0 } }
    yield { type: 'finish', reason: { kind: toolCall ? 'tool-calls' : 'stop' } }
  }
}

export const name = 'mock-llm'
export const inject = ['llm']
export function apply(ctx) {
  ctx.llm.registerAdapter([PROVIDER], new MockAdapter())
  console.log('[mock-llm] registered provider "mock" with model', MODEL)
}
