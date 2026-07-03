import type {
  ApiResponse,
  ExecuteSapInventoryResult,
  SapInventoryParseResult,
} from './types'

async function requestJson<T>(url: string, init?: RequestInit): Promise<ApiResponse<T>> {
  const response = await fetch(url, init)
  if (!response.ok) {
    throw new Error(`请求失败：HTTP ${response.status}`)
  }
  return response.json()
}

export async function importExcel(file: File): Promise<ApiResponse<SapInventoryParseResult>> {
  const formData = new FormData()
  formData.append('file', file)
  return requestJson('/api/sap-inventory/import', {
    method: 'POST',
    body: formData,
  })
}

export async function executeSapInventory(
  factoryName: string,
  warehouseName: string,
): Promise<ApiResponse<ExecuteSapInventoryResult>> {
  return requestJson('/api/sap-inventory/execute', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ factoryName, warehouseName }),
  })
}

export function downloadTemplate() {
  window.open('/api/sap-inventory/template', '_blank')
}
