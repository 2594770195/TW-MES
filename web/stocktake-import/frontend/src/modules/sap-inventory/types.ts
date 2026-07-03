import type { ApiResponse } from '../stocktake/types'

export type { ApiResponse }

export interface SapInventoryRow {
  rowNo: number
  factoryName: string
  workcenterName: string
  productName: string
  lotSN: string
  productInventoryNum?: number | null
  checkNum?: number | null
  lockQty?: number | null
  uomName?: string | null
  storageDate?: string | null
  note?: string | null
}

export interface SapInventoryParseResult {
  rows: SapInventoryRow[]
  errors: string[]
  totalRows: number
}

export interface ExecuteSapInventoryResult {
  factoryName: string
  warehouseName: string
}
