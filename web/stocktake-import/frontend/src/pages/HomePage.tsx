import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { checkHealth } from '../api/health'
import { DbStatusBadge, type DbConnectionStatus } from '../components/DbStatusBadge'
import { moduleEntries, type ModuleIcon } from '../config/modules'

function ModuleIconBadge({ icon }: { icon: ModuleIcon }) {
  const labels: Record<ModuleIcon, string> = {
    inventory: '盘',
    api: 'API',
    tools: '工具',
  }

  return (
    <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-slate-900 text-sm font-semibold text-white">
      {labels[icon]}
    </div>
  )
}

export default function HomePage() {
  const navigate = useNavigate()
  const [dbStatus, setDbStatus] = useState<DbConnectionStatus>('checking')
  const [database, setDatabase] = useState<string>()
  const [environment, setEnvironment] = useState<string>()

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

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-6">
          <div>
            <h1 className="text-3xl font-semibold text-slate-900">MES 工具箱</h1>
            <p className="mt-2 text-sm text-slate-500">
              选择下方功能入口，进入对应的 MES 辅助工具
            </p>
          </div>
          <DbStatusBadge
            status={dbStatus}
            database={database}
            environment={environment}
          />
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-6 py-8">
        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {moduleEntries.map((entry) => (
            <article
              key={entry.id}
              className={`flex flex-col rounded-2xl border bg-white p-6 shadow-sm ${
                entry.enabled
                  ? 'border-slate-200'
                  : 'border-slate-100 opacity-75'
              }`}
            >
              <ModuleIconBadge icon={entry.icon} />
              <h2 className="mt-4 text-lg font-semibold text-slate-900">{entry.title}</h2>
              <p className="mt-2 flex-1 text-sm text-slate-500">{entry.description}</p>
              {entry.enabled ? (
                <button
                  type="button"
                  onClick={() => navigate(entry.path)}
                  className="mt-6 w-full rounded-lg bg-slate-900 px-4 py-2.5 text-sm font-medium text-white hover:bg-slate-800"
                >
                  进入
                </button>
              ) : (
                <span className="mt-6 inline-block w-full rounded-lg bg-slate-100 px-4 py-2.5 text-center text-sm font-medium text-slate-400">
                  即将上线
                </span>
              )}
            </article>
          ))}
        </div>
      </main>
    </div>
  )
}
