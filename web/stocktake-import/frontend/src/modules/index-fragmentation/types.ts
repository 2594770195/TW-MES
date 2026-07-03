export interface ApiResponse<T> {
  code: number
  message: string
  data?: T
}

export interface IndexFragmentationRow {
  schemaName: string
  tableName: string
  indexName: string
  fragmentationPercent: number
}

export interface IndexFragmentationQueryResult {
  minFragmentationPercent: number
  totalCount: number
  rows: IndexFragmentationRow[]
}
