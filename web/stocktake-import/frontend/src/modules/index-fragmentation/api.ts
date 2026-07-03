import type { ApiResponse } from '../stocktake/types'
import type { IndexFragmentationQueryResult } from './types'

export async function queryIndexFragmentation(
  minPercent = 80,
): Promise<ApiResponse<IndexFragmentationQueryResult>> {
  const response = await fetch(
    `/api/index-fragmentation/query?minPercent=${encodeURIComponent(String(minPercent))}`,
  )
  if (!response.ok) {
    throw new Error(`请求失败：HTTP ${response.status}`)
  }
  return response.json()
}