// ============================================================================
// Main Application Component
// ============================================================================

import { useEffect } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { 
  createBrowserRouter, 
  RouterProvider,
  Outlet,
} from 'react-router-dom';
import { Sidebar } from './components/layout/Sidebar';
import { Header } from './components/layout/Header';
import Dashboard from './pages/Dashboard';
import LiveTrading from './pages/LiveTrading';
import Backtests from './pages/Backtests';
import AIConfig from './pages/AIConfig';
import Settings from './pages/Settings';
import { useAppStore } from './stores/app';
import { useSystemHealth } from './hooks/useApi';

// Create a query client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60,
      retry: 3,
      refetchOnWindowFocus: false,
    },
  },
});

// Connection status provider - fetches health to determine connection status
function ConnectionProvider({ children }: { children: React.ReactNode }) {
  const { setWsConnected, setSystemHealth, setKillSwitchActive } = useAppStore();
  const { data: health, isSuccess, isError } = useSystemHealth();

  useEffect(() => {
    // Update connection status based on health check
    if (isSuccess && health) {
      setWsConnected(true);
      setSystemHealth(health);
      setKillSwitchActive(health.metrics?.kill_switch_active ?? false);
    } else if (isError) {
      setWsConnected(false);
      setSystemHealth(null);
    }
  }, [isSuccess, isError, health, setWsConnected, setSystemHealth, setKillSwitchActive]);

  return <>{children}</>;
}

// Layout component
function Layout() {
  return (
    <div className="flex h-screen bg-gray-950 text-white overflow-hidden">
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Header />
        <main className="flex-1 overflow-auto p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

// Create router
const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'live', element: <LiveTrading /> },
      { path: 'trading', element: <LiveTrading /> }, // Alias for /live
      { path: 'backtests', element: <Backtests /> },
      { path: 'ai', element: <AIConfig /> },
      { path: 'settings', element: <Settings /> },
    ],
  },
]);

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ConnectionProvider>
        <RouterProvider router={router} />
      </ConnectionProvider>
    </QueryClientProvider>
  );
}

export default App;
