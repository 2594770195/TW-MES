export interface StocktakeRow {
  rowNo: number
  factoryName: string
  warehouseName: string
  productNo: string
  stockQty: number
  frozenQty: number
  uomName: string
  sapBatchNo: string
  lotSN?: string | null
  productionDate?: string | null
}

export interface ApiResponse<T> {
  code: number
  message: string
  data?: T
}

export interface ParseExcelResult {
  rows: StocktakeRow[]
  errors: string[]
  totalRows: number
}

export interface ExecuteStocktakeResult {
  rawJson: string
  parsed?: StocktakeProcedureResult
}

export interface WarehouseDetail {
  factoryName?: string
  workcenterId?: string
  workcenterName?: string
  status?: string
  errorMsg?: string
  totalRows?: number
  updatedRows?: number
  insertedRows?: number
  removedRows?: number
}

export interface StocktakeProcedureResult {
  result?: boolean
  message?: string
  batchNo?: string
  totalWarehouses?: number
  successWarehouses?: number
  failedWarehouses?: number
  details?: WarehouseDetail[]
}

export interface CheckDetail {
  checkType?: string
  factoryName?: string
  warehouseName?: string
  productNo?: string
  sapBatchNo?: string
  expectedQty?: number | null
  actualQty?: number | null
  diffQty?: number | null
}

export interface StocktakeCheckResult {
  result?: boolean
  message?: string
  totalRows?: number
  issueCount?: number
  details?: CheckDetail[]
}
