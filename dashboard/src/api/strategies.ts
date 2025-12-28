import api from './index'

export interface Strategy {
  id: string
  name: string
  description: string
  category: string
  status: 'running' | 'stopped' | 'unknown'
  parameters?: Record<string, unknown>
}

export interface StrategyListResponse {
  strategies: Strategy[]
  count: number
}

export async function listStrategies(): Promise<StrategyListResponse> {
  const response = await api.get('/strategies')
  return response.data
}

export async function getStrategy(id: string): Promise<Strategy> {
  const response = await api.get(`/strategies/${id}`)
  return response.data
}

export async function runStrategy(id: string): Promise<{ message: string }> {
  const response = await api.post(`/strategies/${id}/run`)
  return response.data
}

export async function getStrategyParams(id: string): Promise<Record<string, unknown>> {
  const response = await api.get(`/strategies/${id}/params`)
  return response.data
}
