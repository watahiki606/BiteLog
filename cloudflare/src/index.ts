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

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// CORS設定（PagesドメインとローカルDevを許可）
app.use('*', cors({
  origin: (origin) => {
    const allowed = [
      'https://bitelog-admin.pages.dev',
      'http://localhost:3000',
      'http://localhost:8788',
    ];
    return allowed.includes(origin ?? '') ? origin : '';
  },
  allowHeaders: ['Content-Type', 'Authorization'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
}));

// ルート登録
app.route('/api/auth', auth);
app.route('/api/food-masters', foodMasters);
app.route('/api/log-items', logItems);
app.route('/api/nutrition-goals', nutritionGoals);
app.route('/api/user-data', userData);
app.route('/api/csv', csvImport);
app.route('/api/ai', aiAnalyze);

// ヘルスチェック
app.get('/health', (c) => c.json({ ok: true }));

export default app;
