import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { Bindings, Variables } from './types';
import auth from './routes/auth';
import foodMasters from './routes/foodMasters';
import logItems from './routes/logItems';
import nutritionGoals from './routes/nutritionGoals';
import userData from './routes/userData';
import csvImport from './routes/csvImport';
import aiAnalyze from './routes/aiAnalyze';
import bodyMeasurements from './routes/bodyMeasurements';

const base = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// CORS設定（PagesドメインとローカルDevを許可）
base.use('*', cors({
  origin: (origin) => {
    const allowed = [
      'https://bitelog-web.pages.dev',
      'http://localhost:3000',
      'http://localhost:5173',
      'http://localhost:8788',
    ];
    return allowed.includes(origin ?? '') ? origin : '';
  },
  allowHeaders: ['Content-Type', 'Authorization'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
}));

// ルート登録（メソッドチェーンで型スキーマを蓄積する）
const app = base
  .route('/api/auth', auth)
  .route('/api/food-masters', foodMasters)
  .route('/api/log-items', logItems)
  .route('/api/nutrition-goals', nutritionGoals)
  .route('/api/user-data', userData)
  .route('/api/csv', csvImport)
  .route('/api/ai', aiAnalyze)
  .route('/api/body-measurements', bodyMeasurements)
  .get('/health', (c) => c.json({ ok: true }));

export default app;
export type AppType = typeof app;
