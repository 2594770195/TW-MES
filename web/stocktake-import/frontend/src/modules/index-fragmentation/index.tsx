import { useCallback, useEffect, useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { checkHealth } from '../../api/health'
import { DbStatusBadge, type DbConnectionStatus } from '../../components/DbStatusBadge'
import type { ModuleLayoutContext } from '../../layout/ModuleLayout'
import { queryIndexFragmentation } from './api'
import type { IndexFragmentationRow } from './types'

function formatPercent(value: number): string {
  return `${value.toFixed(2)}%`
}

function fragmentationClass(percent: number): string {
  if (percent >= 90) {
    return 'font-semibold text-red-700'
  }
  if (percent >= 80) {
    return 'font-medium text-red-600'
  }
  return 'text-slate-700'
}

export default function IndexFragmentationPage() {
  const { setHeaderExtra } = useOutletContext<ModuleLayoutContext>()
  const [dbStatus, setDbStatus] = useState<DbConnectionStatus>('checking')
  const [database, setDatabase] = useState<string>()
  const [environment, setEnvironment] = useState<string>()
  const [minPercent, setMinPercent] = useState('80')
  const [rows, setRows] = useState<IndexFragmentationRow[]>([])
  const [totalCount, setTotalCount] = useState(0)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [queried, setQueried] = useState(false)

  useEffect(() => {
    checkHealth()
      .then((res) => {
        if (res.code === 0) {
          setDbStatus('ok')
          setDatabase(res.data?.database)
          setEnvironment(res.data?.environment)
          return
        }
        setDbStatus('fail')
      })
      .catch(() => setDbStatus('fail'))
  }, [])

  useEffect(() => {
    setHeaderExtra(
      <DbStatusBadge status={dbStatus} database={database} environment={environment} />,
    )
    return () => setHeaderExtra(null)
  }, [dbStatus, database, environment, setHeaderExtra])

  const handleQuery = useCallback(async () => {
    const threshold = Number(minPercent)
    if (Number.isNaN(threshold) || threshold < 0 || threshold > 100) {
      setError('碎片百分比阈值须在 0～100 之间')
      return
    }

    setLoading(true)
    setError('')
    setMessage('')

    try {
      const res = await queryIndexFragmentation(threshold)
      setQueried(true)
      if (res.code === 0 && res.data) {
        setRows(res.data.rows)
        setTotalCount(res.data.totalCount)
        setMessage(res.message)
        return
      }
      setRows([])
      setTotalCount(0)
      setError(res.message || '查询失败')
    } catch {
      setRows([])
      setTotalCount(0)
      setError('查询失败，请确认后端服务已启动')
    } finally {
      setLoading(false)
    }
  }, [minPercent])

  return (
    <main className="mx-auto max-w-6xl space-y-4 px-3 py-4">
      <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        <div className="flex flex-wrap items-end gap-4">
          <div>
            <label className="mb-2 block text-sm font-medium text-slate-700">
              碎片百分比阈值（%）
            </label>
            <input
              type="number"
              min={0}
              max={100}
              step={1}
              value={minPercent}
              onChange={(e) => setMinPercent(e.target.value)}
              className="w-32 rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            />
          </div>
          <button
            type="button"
            onClick={handleQuery}
            disabled={loading || dbStatus !== 'ok'}
            className="rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-400"
          >
            {loading ? '查询中...' : queried ? '刷新' : '查询'}
          </button>
        </div>

        {error && (
          <div className="mt-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </div>
        )}

        {message && !error && (
          <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
            {message}
          </div>
        )}

        <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          查询当前连接数据库中碎片率超过阈值的索引（只读）。默认阈值 80%，结果按碎片率从高到低排序。
        </div>
      </section>

      {queried && !error && (
        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-semibold">查询结果</h2>
              <p className="text-sm text-slate-500">
                共 {totalCount} 个索引碎片率超过 {minPercent}%
              </p>
            </div>
          </div>

          {rows.length === 0 ? (
            <p className="text-sm text-slate-500">暂无符合条件的索引。</p>
          ) : (
            <div className="overflow-x-auto rounded-xl border border-slate-200">
              <table className="min-w-full divide-y divide-slate-200 text-sm">
                <thead className="bg-slate-50">
                  <tr>
                    <th className="px-3 py-2 text-left font-medium text-slate-600">架构</th>
                    <th className="px-3 py-2 text-left font-medium text-slate-600">表名</th>
                    <th className="px-3 py-2 text-left font-medium text-slate-600">索引名</th>
                    <th className="px-3 py-2 text-right font-medium text-slate-600">碎片百分比</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 bg-white">
                  {rows.map((row) => {
                    const key = `${row.schemaName}.${row.tableName}.${row.indexName}`
                    return (
                      <tr key={key} className="hover:bg-slate-50">
                        <td className="px-3 py-2">{row.schemaName}</td>
                        <td className="px-3 py-2">{row.tableName}</td>
                        <td className="px-3 py-2">{row.indexName}</td>
                        <td
                          className={`px-3 py-2 text-right ${fragmentationClass(row.fragmentationPercent)}`}
                        >
                          {formatPercent(row.fragmentationPercent)}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}
    </main>
  )
}
