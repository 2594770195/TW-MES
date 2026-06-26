import { useEffect, useMemo, useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { checkHealth } from '../../api/health'
import { DbStatusBadge, type DbConnectionStatus } from '../../components/DbStatusBadge'
import type { ModuleLayoutContext } from '../../layout/ModuleLayout'
import {
  downloadTemplate,
  executeStocktake,
  importExcel,
} from './api'
import type { StocktakeProcedureResult, StocktakeRow } from './types'

export default function StocktakePage() {
  const { setHeaderExtra } = useOutletContext<ModuleLayoutContext>()
  const [dbStatus, setDbStatus] = useState<DbConnectionStatus>('checking')
  const [database, setDatabase] = useState<string>()
  const [environment, setEnvironment] = useState<string>()
  const [file, setFile] = useState<File | null>(null)
  const [rows, setRows] = useState<StocktakeRow[]>([])
  const [parseErrors, setParseErrors] = useState<string[]>([])
  const [imported, setImported] = useState(false)
  const [createUserId, setCreateUserId] = useState('')
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)
  const [procedureResult, setProcedureResult] = useState<StocktakeProcedureResult | null>(null)

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
      <DbStatusBadge
        status={dbStatus}
        database={database}
        environment={environment}
      />,
    )
    return () => setHeaderExtra(null)
  }, [dbStatus, database, environment, setHeaderExtra])

  const canExecute = imported && rows.length > 0 && parseErrors.length === 0 && !loading

  const warehouseSummary = useMemo(() => {
    const map = new Map<string, number>()
    rows.forEach((row) => {
      const key = `${row.factoryName} / ${row.warehouseName}`
      map.set(key, (map.get(key) ?? 0) + 1)
    })
    return Array.from(map.entries())
  }, [rows])

  async function handleImport() {
    if (!file) {
      setMessage('请先选择 Excel 文件')
      return
    }

    setLoading(true)
    setMessage('')
    setProcedureResult(null)
    setImported(false)

    try {
      const res = await importExcel(file, createUserId)
      setRows(res.data?.rows ?? [])
      setParseErrors(res.data?.errors ?? [])
      setImported(res.code === 0)
      setMessage(res.message)
    } catch {
      setMessage('导入失败，请确认后端服务已启动')
      setRows([])
      setParseErrors([])
      setImported(false)
    } finally {
      setLoading(false)
    }
  }

  async function handleExecute(dryRun: boolean) {
    if (!canExecute) {
      return
    }

    if (!dryRun) {
      const confirmed = window.confirm(
        '正式更新会直接修改数据库库存，建议先执行预览。确定要继续正式更新吗？',
      )
      if (!confirmed) {
        return
      }
    }

    setLoading(true)
    setMessage('')
    setProcedureResult(null)

    try {
      const res = await executeStocktake(dryRun, createUserId)
      setMessage(res.message)
      setProcedureResult(res.data?.parsed ?? null)
    } catch {
      setMessage('执行失败，请检查网络和后端日志')
    } finally {
      setLoading(false)
    }
  }

  return (
    <main className="mx-auto max-w-6xl space-y-4 px-3 py-4">
      <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div className="space-y-4">
            <div>
              <label className="mb-2 block text-sm font-medium text-slate-700">
                选择盘点 Excel
              </label>
              <input
                type="file"
                accept=".xlsx,.xlsm"
                onChange={(e) => {
                  setFile(e.target.files?.[0] ?? null)
                  setImported(false)
                  setRows([])
                  setParseErrors([])
                  setProcedureResult(null)
                }}
                className="block w-full max-w-md text-sm file:mr-4 file:rounded-lg file:border-0 file:bg-slate-900 file:px-4 file:py-2 file:text-sm file:font-medium file:text-white hover:file:bg-slate-800"
              />
            </div>
            <div>
              <label className="mb-2 block text-sm font-medium text-slate-700">
                操作人 ID（可选，12 位）
              </label>
              <input
                type="text"
                maxLength={12}
                value={createUserId}
                onChange={(e) => setCreateUserId(e.target.value)}
                placeholder="例如：USER00000001"
                className="w-full max-w-md rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </div>

          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              onClick={downloadTemplate}
              className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
            >
              下载模板
            </button>
            <button
              type="button"
              onClick={handleImport}
              disabled={!file || loading}
              className="rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-400"
            >
              导入 Excel
            </button>
            <button
              type="button"
              onClick={() => handleExecute(true)}
              disabled={!canExecute}
              className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:bg-blue-300"
            >
              预览（DryRun）
            </button>
            <button
              type="button"
              onClick={() => handleExecute(false)}
              disabled={!canExecute}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-500 disabled:cursor-not-allowed disabled:bg-red-300"
            >
              正式更新
            </button>
          </div>
        </div>

        {message && (
          <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
            {message}
          </div>
        )}

        <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          建议流程：下载模板 → 填写盘点数据 → 导入 Excel（写入数据库）→ 先点「预览」确认结果 → 再点「正式更新」。
          正式更新前请确认 Excel 已覆盖该仓库全部物料。
        </div>
      </section>

      {parseErrors.length > 0 && (
        <section className="rounded-2xl border border-red-200 bg-red-50 p-6">
          <h2 className="text-lg font-semibold text-red-800">导入错误</h2>
          <ul className="mt-3 space-y-1 text-sm text-red-700">
            {parseErrors.map((error) => (
              <li key={error}>• {error}</li>
            ))}
          </ul>
        </section>
      )}

      {rows.length > 0 && (
        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-semibold">已导入数据</h2>
              <p className="text-sm text-slate-500">共 {rows.length} 行，已写入 TempStocktakeData</p>
            </div>
            <div className="flex flex-wrap gap-2">
              {warehouseSummary.map(([name, count]) => (
                <span
                  key={name}
                  className="rounded-full bg-slate-100 px-3 py-1 text-xs text-slate-600"
                >
                  {name}：{count} 行
                </span>
              ))}
            </div>
          </div>

          <div className="overflow-x-auto rounded-xl border border-slate-200">
            <table className="min-w-full divide-y divide-slate-200 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">行号</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">工厂</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">仓库</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">物料号</th>
                  <th className="px-3 py-2 text-right font-medium text-slate-600">库存数量</th>
                  <th className="px-3 py-2 text-right font-medium text-slate-600">冻结数量</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">单位</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">SAP批号</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 bg-white">
                {rows.slice(0, 100).map((row) => (
                  <tr key={row.rowNo} className="hover:bg-slate-50">
                    <td className="px-3 py-2">{row.rowNo}</td>
                    <td className="px-3 py-2">{row.factoryName}</td>
                    <td className="px-3 py-2">{row.warehouseName}</td>
                    <td className="px-3 py-2">{row.productNo}</td>
                    <td className="px-3 py-2 text-right">{row.stockQty}</td>
                    <td className="px-3 py-2 text-right">{row.frozenQty ?? 0}</td>
                    <td className="px-3 py-2">{row.uomName}</td>
                    <td className="px-3 py-2">{row.sapBatchNo}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {rows.length > 100 && (
            <p className="mt-2 text-sm text-slate-500">
              仅展示前 100 行，导入时会处理全部 {rows.length} 行。
            </p>
          )}
        </section>
      )}

      {procedureResult && (
        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-4 flex flex-wrap items-center gap-3">
            <h2 className="text-lg font-semibold">执行结果</h2>
            <span
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                procedureResult.result
                  ? 'bg-emerald-100 text-emerald-700'
                  : 'bg-red-100 text-red-700'
              }`}
            >
              {procedureResult.result ? '成功' : '失败'}
            </span>
            {procedureResult.batchNo && (
              <span className="text-sm text-slate-500">批次号：{procedureResult.batchNo}</span>
            )}
          </div>

          <p className="text-sm text-slate-700">{procedureResult.message}</p>

          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            <div className="rounded-xl bg-slate-50 p-4">
              <div className="text-xs text-slate-500">总仓库数</div>
              <div className="mt-1 text-2xl font-semibold">{procedureResult.totalWarehouses ?? 0}</div>
            </div>
            <div className="rounded-xl bg-emerald-50 p-4">
              <div className="text-xs text-emerald-700">成功</div>
              <div className="mt-1 text-2xl font-semibold text-emerald-800">
                {procedureResult.successWarehouses ?? 0}
              </div>
            </div>
            <div className="rounded-xl bg-red-50 p-4">
              <div className="text-xs text-red-700">失败</div>
              <div className="mt-1 text-2xl font-semibold text-red-800">
                {procedureResult.failedWarehouses ?? 0}
              </div>
            </div>
          </div>

          {procedureResult.details && procedureResult.details.length > 0 && (
            <div className="mt-6 overflow-x-auto rounded-xl border border-slate-200">
              <table className="min-w-full divide-y divide-slate-200 text-sm">
                <thead className="bg-slate-50">
                  <tr>
                    <th className="px-3 py-2 text-left">工厂</th>
                    <th className="px-3 py-2 text-left">仓库</th>
                    <th className="px-3 py-2 text-left">状态</th>
                    <th className="px-3 py-2 text-right">盘点行</th>
                    <th className="px-3 py-2 text-right">更新</th>
                    <th className="px-3 py-2 text-right">新增</th>
                    <th className="px-3 py-2 text-right">置出库</th>
                    <th className="px-3 py-2 text-left">错误信息</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {procedureResult.details.map((item, index) => (
                    <tr key={`${item.workcenterId ?? index}-${index}`}>
                      <td className="px-3 py-2">{item.factoryName}</td>
                      <td className="px-3 py-2">{item.workcenterName}</td>
                      <td className="px-3 py-2">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs ${
                            item.status === 'success'
                              ? 'bg-emerald-100 text-emerald-700'
                              : 'bg-red-100 text-red-700'
                          }`}
                        >
                          {item.status}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-right">{item.totalRows ?? 0}</td>
                      <td className="px-3 py-2 text-right">{item.updatedRows ?? 0}</td>
                      <td className="px-3 py-2 text-right">{item.insertedRows ?? 0}</td>
                      <td className="px-3 py-2 text-right">{item.removedRows ?? 0}</td>
                      <td className="px-3 py-2 text-red-600">{item.errorMsg || '-'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}
    </main>
  )
}
