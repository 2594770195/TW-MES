export type ModuleIcon = 'inventory' | 'api' | 'tools'

export interface ModuleEntry {
  id: string
  title: string
  description: string
  path: string
  icon: ModuleIcon
  enabled: boolean
}

export const moduleEntries: ModuleEntry[] = [
  {
    id: 'stocktake',
    title: '库存盘点导入',
    description: '上传 Excel，预览或正式更新 WW_RMInventory',
    path: '/stocktake',
    icon: 'inventory',
    enabled: true,
  },
  {
    id: 'api-tester',
    title: '接口测试',
    description: '发送 HTTP 请求，查看响应结果',
    path: '/api-tester',
    icon: 'api',
    enabled: false,
  },
]

export function getModuleByPath(path: string): ModuleEntry | undefined {
  return moduleEntries.find((entry) => entry.path === path)
}
