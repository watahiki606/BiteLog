import { useState, useCallback } from 'react';
import { getSession } from '@/lib/auth';
import SetupModal from '@/components/SetupModal';
import Sidebar from '@/components/Sidebar';
import Toast, { type ToastMessage } from '@/components/Toast';
import FoodMasterPage from '@/pages/FoodMasterPage';
import MealLogPage from '@/pages/MealLogPage';
import NutritionGoalsPage from '@/pages/NutritionGoalsPage';

type Tab = 'food' | 'log' | 'goals';

export default function App() {
  const [session, setSession] = useState(getSession());
  const [activeTab, setActiveTab] = useState<Tab>('food');
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  const addToast = useCallback((msg: Omit<ToastMessage, 'id'>) => {
    const id = crypto.randomUUID();
    setToasts((prev) => [...prev, { ...msg, id }]);
  }, []);

  const removeToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  if (!session) {
    return <SetupModal onAuthenticated={() => setSession(getSession())} />;
  }

  return (
    <div className="flex h-full w-full overflow-hidden cyber-grid scanlines">
      <Sidebar
        activeTab={activeTab}
        onTabChange={setActiveTab}
        onLogout={() => setSession(null)}
        isAdmin={session.isAdmin}
      />
      <main className="flex-1 flex flex-col overflow-hidden bg-bg-deep">
        {activeTab === 'food' && <FoodMasterPage onToast={addToast} isAdmin={session.isAdmin} />}
        {activeTab === 'log' && <MealLogPage onToast={addToast} />}
        {activeTab === 'goals' && <NutritionGoalsPage onToast={addToast} />}
      </main>
      <Toast toasts={toasts} onRemove={removeToast} />
    </div>
  );
}
