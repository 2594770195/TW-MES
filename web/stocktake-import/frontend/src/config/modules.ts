export type ModuleIcon = 'inventory' | 'api' | 'tools'

export interface ModuleEntry {
  id: string
  title: string
  description: string
  path: string
  icon: ModuleIcon
  enabled: boolean
  /** 为 true 时不在首页展示（逻辑已合并至其他模块等场景） */
  hidden?: boolean
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
    id: 'sap-inventory',
    title: '半成品盘点',
    description: '导入 SAP 半成品库存，按工厂仓库更新 WW_RMInventory',
    path: '/sap-inventory',
    icon: 'inventory',
    enabled: false,
    hidden: true, // 半成品逻辑已合并至「库存盘点导入」
  },
  {
    id: 'index-fragmentation',
    title: '索引碎片查询',
    description: '查询当前库中碎片率超过阈值的表及索引（只读）',
    path: '/index-fragmentation',
    icon: 'tools',
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
