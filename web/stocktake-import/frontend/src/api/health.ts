import type { ApiResponse } from '../modules/stocktake/types'

export interface HealthData {
  database: string
  environment: string
}

export async function checkHealth(): Promise<ApiResponse<HealthData>> {
  const response = await fetch('/api/stocktake/health')
  if (!response.ok) {
    throw new Error(`请求失败：HTTP ${response.status}`)
  }
  return response.json()
}
