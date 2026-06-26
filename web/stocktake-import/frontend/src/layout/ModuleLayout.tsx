import { useEffect, useState, type ReactNode } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { getModuleByPath } from '../config/modules'

export interface ModuleLayoutContext {
  setHeaderExtra: (node: ReactNode) => void
}

export function ModuleLayout() {
  const location = useLocation()
  const module = getModuleByPath(location.pathname)
  const [headerExtra, setHeaderExtra] = useState<ReactNode>(null)

  useEffect(() => {
    setHeaderExtra(null)
  }, [location.pathname])

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto max-w-6xl px-6 py-3">
          <Link
            to="/"
            className="inline-flex items-center gap-1 text-sm font-medium text-slate-600 hover:text-slate-900"
          >
            ← 返回首页
          </Link>
        </div>
      </nav>

      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-5">
          <div>
            <h1 className="text-2xl font-semibold text-slate-900">
              {module?.title ?? '功能模块'}
            </h1>
            <p className="mt-1 text-sm text-slate-500">
              {module?.description ?? ''}
            </p>
          </div>
          {headerExtra}
        </div>
      </header>

      <Outlet context={{ setHeaderExtra } satisfies ModuleLayoutContext} />
    </div>
  )
}
