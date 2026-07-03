import { useEffect, useMemo, useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { checkHealth } from '../../api/health'
import { DbStatusBadge, type DbConnectionStatus } from '../../components/DbStatusBadge'
import type { ModuleLayoutContext } from '../../layout/ModuleLayout'
import { downloadTemplate, executeSapInventory, importExcel } from './api'
import type { SapInventoryRow } from './types'

export default function SapInventoryPage() {
  const { setHeaderExtra } = useOutletContext<ModuleLayoutContext>()
  const [dbStatus, setDbStatus] = useState<DbConnectionStatus>('checking')
  const [database, setDatabase] = useState<string>()
  const [environment, setEnvironment] = useState<string>()
  const [file, setFile] = useState<File | null>(null)
  const [rows, setRows] = useState<SapInventoryRow[]>([])
  const [parseErrors, setParseErrors] = useState<string[]>([])
  const [imported, setImported] = useState(false)
  const [factoryName, setFactoryName] = useState('')
  const [warehouseName, setWarehouseName] = useState('')
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)

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

  const warehouseSummary = useMemo(() => {
    const map = new Map<string, number>()
    rows.forEach((row) => {
      const key = `${row.factoryName} / ${row.workcenterName}`
      map.set(key, (map.get(key) ?? 0) + 1)
    })
    return Array.from(map.entries())
  }, [rows])

  const canExecute =
    factoryName.trim().length > 0 && warehouseName.trim().length > 0 && !loading

  async function handleImport() {
    if (!file) {
      setMessage('请先选择 Excel 文件')
      return
    }

    setLoading(true)
    setMessage('')
    setImported(false)

    try {
      const res = await importExcel(file)
      const importedRows = res.data?.rows ?? []
      setRows(importedRows)
      setParseErrors(res.data?.errors ?? [])
      setImported(res.code === 0)
      setMessage(res.message)

      // 导入成功且只有一个工厂仓库时，自动填入执行表单
      if (res.code === 0 && importedRows.length > 0) {
        const factories = new Set(importedRows.map((r) => r.factoryName))
        const warehouses = new Set(importedRows.map((r) => r.workcenterName))
        if (factories.size === 1) {
          setFactoryName([...factories][0])
        }
        if (warehouses.size === 1) {
          setWarehouseName([...warehouses][0])
        }
      }
    } catch {
      setMessage('导入失败，请确认后端服务已启动')
      setRows([])
      setParseErrors([])
      setImported(false)
    } finally {
      setLoading(false)
    }
  }

  async function handleExecute() {
    if (!canExecute) {
      return
    }

    const confirmed = window.confirm(
      `将按「${factoryName.trim()} / ${warehouseName.trim()}」直接更新 WW_RMInventory 库存，确定继续吗？`,
    )
    if (!confirmed) {
      return
    }

    setLoading(true)
    setMessage('')

    try {
      const res = await executeSapInventory(factoryName.trim(), warehouseName.trim())
      setMessage(res.message)
    } catch {
      setMessage('执行失败，请检查网络和后端日志')
    } finally {
      setLoading(false)
    }
  }

  return (
    <main className="mx-auto max-w-6xl space-y-4 px-3 py-4">
      <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        <div className="space-y-4">
          <div>
            <label className="mb-2 block text-sm font-medium text-slate-700">
              选择半成品盘点 Excel
            </label>
            <div className="flex flex-wrap items-center gap-3">
              <input
                type="file"
                accept=".xlsx,.xlsm"
                onChange={(e) => {
                  setFile(e.target.files?.[0] ?? null)
                  setImported(false)
                  setRows([])
                  setParseErrors([])
                }}
                className="block w-full max-w-md text-sm file:mr-4 file:rounded-lg file:border-0 file:bg-slate-900 file:px-4 file:py-2 file:text-sm file:font-medium file:text-white hover:file:bg-slate-800"
              />
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
                导入到 SAP_PRODUCT_INVENTORY
              </button>
            </div>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label className="mb-2 block text-sm font-medium text-slate-700">工厂</label>
              <input
                type="text"
                value={factoryName}
                onChange={(e) => setFactoryName(e.target.value)}
                placeholder="例如：一厂"
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              />
            </div>
            <div>
              <label className="mb-2 block text-sm font-medium text-slate-700">仓库</label>
              <input
                type="text"
                value={warehouseName}
                onChange={(e) => setWarehouseName(e.target.value)}
                placeholder="例如：半成品仓"
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </div>

          <div>
            <button
              type="button"
              onClick={handleExecute}
              disabled={!canExecute}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-500 disabled:cursor-not-allowed disabled:bg-red-300"
            >
              执行盘点更新
            </button>
          </div>
        </div>

        {message && (
          <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
            {message}
          </div>
        )}

        <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          建议流程：下载模板 → 填写半成品库存数据 → 导入（写入 SAP_PRODUCT_INVENTORY）→ 填写/确认工厂、仓库 → 执行盘点更新。
          执行会直接修改 WW_RMInventory，请确认导入数据已覆盖该仓库全部批次。
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

      {imported && rows.length > 0 && (
        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-semibold">已导入数据</h2>
              <p className="text-sm text-slate-500">共 {rows.length} 行，已写入 SAP_PRODUCT_INVENTORY</p>
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
                  <th className="px-3 py-2 text-left font-medium text-slate-600">物料</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">批号</th>
                  <th className="px-3 py-2 text-right font-medium text-slate-600">在库数量</th>
                  <th className="px-3 py-2 text-right font-medium text-slate-600">质检数量</th>
                  <th className="px-3 py-2 text-right font-medium text-slate-600">锁定数量</th>
                  <th className="px-3 py-2 text-left font-medium text-slate-600">单位</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 bg-white">
                {rows.slice(0, 100).map((row) => (
                  <tr key={row.rowNo} className="hover:bg-slate-50">
                    <td className="px-3 py-2">{row.rowNo}</td>
                    <td className="px-3 py-2">{row.factoryName}</td>
                    <td className="px-3 py-2">{row.workcenterName}</td>
                    <td className="px-3 py-2">{row.productName}</td>
                    <td className="px-3 py-2">{row.lotSN}</td>
                    <td className="px-3 py-2 text-right">{row.productInventoryNum ?? '-'}</td>
                    <td className="px-3 py-2 text-right">{row.checkNum ?? '-'}</td>
                    <td className="px-3 py-2 text-right">{row.lockQty ?? '-'}</td>
                    <td className="px-3 py-2">{row.uomName ?? '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {rows.length > 100 && (
            <p className="mt-2 text-sm text-slate-500">
              仅展示前 100 行，已导入全部 {rows.length} 行。
            </p>
          )}
        </section>
      )}
    </main>
  )
}
