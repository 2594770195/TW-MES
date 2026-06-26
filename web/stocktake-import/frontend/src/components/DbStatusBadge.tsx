export type DbConnectionStatus = 'checking' | 'ok' | 'fail'

export interface DbHealthInfo {
  database?: string
  environment?: string
}

interface DbStatusBadgeProps extends DbHealthInfo {
  status: DbConnectionStatus
}

function statusLabel(status: DbConnectionStatus) {
  if (status === 'checking') return '检测中...'
  if (status === 'ok') return '已连接'
  return '连接失败'
}

function environmentClass(environment?: string) {
  if (environment === '生产环境') {
    return 'border-amber-200 bg-amber-50 text-amber-900'
  }
  if (environment === '测试环境') {
    return 'border-sky-200 bg-sky-50 text-sky-900'
  }
  return 'border-slate-200 bg-slate-50 text-slate-700'
}

export function DbStatusBadge({ status, database, environment }: DbStatusBadgeProps) {
  const dotClass =
    status === 'ok'
      ? 'bg-emerald-500'
      : status === 'fail'
        ? 'bg-red-500'
        : 'bg-amber-400'

  const detail =
    status === 'ok' && database
      ? `${environment ? `${environment} · ` : ''}${database} · ${statusLabel(status)}`
      : `数据库：${statusLabel(status)}`

  return (
    <div
      className={`flex items-center gap-2 rounded-lg border px-3 py-2 text-sm ${environmentClass(environment)}`}
    >
      <span className={`inline-flex h-2.5 w-2.5 shrink-0 rounded-full ${dotClass}`} />
      <span>{detail}</span>
    </div>
  )
}
