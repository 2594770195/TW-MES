import { Suspense, lazy } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { ModuleLayout } from './layout/ModuleLayout'
import HomePage from './pages/HomePage'

const StocktakePage = lazy(() => import('./modules/stocktake'))
const SapInventoryPage = lazy(() => import('./modules/sap-inventory'))
const IndexFragmentationPage = lazy(() => import('./modules/index-fragmentation'))

function PageLoader() {
  return (
    <div className="flex min-h-[40vh] items-center justify-center text-sm text-slate-500">
      加载中...
    </div>
  )
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route element={<ModuleLayout />}>
          <Route
            path="/stocktake"
            element={
              <Suspense fallback={<PageLoader />}>
                <StocktakePage />
              </Suspense>
            }
          />
          <Route
            path="/sap-inventory"
            element={
              <Suspense fallback={<PageLoader />}>
                <SapInventoryPage />
              </Suspense>
            }
          />
          <Route
            path="/index-fragmentation"
            element={
              <Suspense fallback={<PageLoader />}>
                <IndexFragmentationPage />
              </Suspense>
            }
          />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}

export default App
