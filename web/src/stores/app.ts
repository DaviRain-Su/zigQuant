// ============================================================================
// Application Store (Zustand)
// ============================================================================

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { SystemHealth, AIStatus, StrategySummary, LiveSummary, BacktestSummary } from '../types/api';

// ============================================================================
// Store Types
// ============================================================================

interface AppState {
  // Connection status
  isConnected: boolean;
  wsConnected: boolean;
  
  // Theme
  theme: 'light' | 'dark' | 'system';
  
  // System health
  systemHealth: SystemHealth | null;
  
  // AI status
  aiStatus: AIStatus | null;
  
  // Strategies
  strategies: StrategySummary[];
  
  // Live sessions
  liveSessions: LiveSummary[];
  
  // Backtests
  backtests: BacktestSummary[];
  
  // Kill switch
  killSwitchActive: boolean;
  
  // Sidebar collapsed
  sidebarCollapsed: boolean;
  
  // Actions
  setConnected: (connected: boolean) => void;
  setWsConnected: (connected: boolean) => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
  setSystemHealth: (health: SystemHealth | null) => void;
  setAIStatus: (status: AIStatus | null) => void;
  setStrategies: (strategies: StrategySummary[]) => void;
  updateStrategy: (strategy: StrategySummary) => void;
  removeStrategy: (id: string) => void;
  setLiveSessions: (sessions: LiveSummary[]) => void;
  updateLiveSession: (session: LiveSummary) => void;
  removeLiveSession: (id: string) => void;
  setBacktests: (backtests: BacktestSummary[]) => void;
  updateBacktest: (backtest: BacktestSummary) => void;
  removeBacktest: (id: string) => void;
  setKillSwitchActive: (active: boolean) => void;
  toggleSidebar: () => void;
}

// ============================================================================
// Store Implementation
// ============================================================================

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      // Initial state
      isConnected: false,
      wsConnected: false,
      theme: 'dark',
      systemHealth: null,
      aiStatus: null,
      strategies: [],
      liveSessions: [],
      backtests: [],
      killSwitchActive: false,
      sidebarCollapsed: false,

      // Actions
      setConnected: (connected) => set({ isConnected: connected }),
      
      setWsConnected: (connected) => set({ wsConnected: connected }),
      
      setTheme: (theme) => {
        set({ theme });
        // Apply theme to document
        if (theme === 'system') {
          const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
          document.documentElement.classList.toggle('dark', prefersDark);
        } else {
          document.documentElement.classList.toggle('dark', theme === 'dark');
        }
      },
      
      setSystemHealth: (health) => set({ systemHealth: health }),
      
      setAIStatus: (status) => set({ aiStatus: status }),
      
      setStrategies: (strategies) => set({ strategies }),
      
      updateStrategy: (strategy) => set((state) => ({
        strategies: state.strategies.map((s) =>
          s.id === strategy.id ? strategy : s
        ),
      })),
      
      removeStrategy: (id) => set((state) => ({
        strategies: state.strategies.filter((s) => s.id !== id),
      })),
      
      setLiveSessions: (sessions) => set({ liveSessions: sessions }),
      
      updateLiveSession: (session) => set((state) => ({
        liveSessions: state.liveSessions.map((s) =>
          s.id === session.id ? session : s
        ),
      })),
      
      removeLiveSession: (id) => set((state) => ({
        liveSessions: state.liveSessions.filter((s) => s.id !== id),
      })),
      
      setBacktests: (backtests) => set({ backtests }),
      
      updateBacktest: (backtest) => set((state) => ({
        backtests: state.backtests.map((b) =>
          b.id === backtest.id ? backtest : b
        ),
      })),
      
      removeBacktest: (id) => set((state) => ({
        backtests: state.backtests.filter((b) => b.id !== id),
      })),
      
      setKillSwitchActive: (active) => set({ killSwitchActive: active }),
      
      toggleSidebar: () => set((state) => ({ 
        sidebarCollapsed: !state.sidebarCollapsed 
      })),
    }),
    {
      name: 'zigquant-app-store',
      partialize: (state) => ({
        theme: state.theme,
        sidebarCollapsed: state.sidebarCollapsed,
      }),
    }
  )
);

export default useAppStore;
