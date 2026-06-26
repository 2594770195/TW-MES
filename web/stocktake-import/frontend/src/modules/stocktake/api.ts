import type {
  ApiResponse,
  ExecuteStocktakeResult,
  ParseExcelResult,
} from './types'

async function requestJson<T>(url: string, init?: RequestInit): Promise<ApiResponse<T>> {
  const response = await fetch(url, init)
  if (!response.ok) {
    throw new Error(`请求失败：HTTP ${response.status}`)
  }
  return response.json()
}

export async function importExcel(
  file: File,
  createUserId: string,
): Promise<ApiResponse<ParseExcelResult>> {
  const formData = new FormData()
  formData.append('file', file)
  formData.append('createUserId', createUserId)
  return requestJson('/api/stocktake/import', {
    method: 'POST',
    body: formData,
  })
}

export async function executeStocktake(
  dryRun: boolean,
  createUserId: string,
): Promise<ApiResponse<ExecuteStocktakeResult>> {
  return requestJson('/api/stocktake/execute', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ dryRun, createUserId }),
  })
}

export function downloadTemplate() {
  window.open('/api/stocktake/template', '_blank')
}
