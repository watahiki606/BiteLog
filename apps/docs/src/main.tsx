import type { RouteRecord } from 'vite-react-ssg'
import { ViteReactSSG } from 'vite-react-ssg'
import './index.css'
import Layout from './components/Layout'
import Home from './pages/Home'
import Support from './pages/Support'
import Privacy from './pages/Privacy'
import Terms from './pages/Terms'

export const routes: RouteRecord[] = [
  {
    path: '/',
    element: <Layout />,
    entry: 'src/components/Layout.tsx',
    children: [
      { index: true, Component: Home },
      { path: 'support', Component: Support },
      { path: 'privacy', Component: Privacy },
      { path: 'terms', Component: Terms },
    ],
  },
]

export const createRoot = ViteReactSSG({ routes })
