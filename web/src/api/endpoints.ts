// ============================================================================
// API Endpoints for zigQuant
// ============================================================================

import apiClient from './client';
import type {
  HealthStatus,
  SystemHealth,
  StrategySummary,
  StrategyRequest,
  StrategyStats,
  BacktestRequest,
  BacktestSummary,
  BacktestResult,
  BacktestDetailedResult,
  LiveRequest,
  LiveSummary,
  LiveStats,
  AIConfig,
  AIStatus,
  ManagerStats,
  KillSwitchResult,
  LoginRequest,
  AuthResponse,
  UserInfo,
  LogsResponse,
  LogLevel,
} from '../types/api';

// ============================================================================
// Health & System
// ============================================================================

export const healthApi = {
  getHealth: () => apiClient.get<HealthStatus>('/health'),
  getReady: () => apiClient.get<{ ready: boolean }>('/ready'),
  getVersion: () => apiClient.get<{ name: string; version: string }>('/version'),
  getSystemHealth: () => apiClient.get<SystemHealth>('/api/v2/system/health'),
};

// ============================================================================
// Logs
// ============================================================================

export const logsApi = {
  getLogs: (options?: { limit?: number; level?: LogLevel }) => {
    const params = new URLSearchParams();
    if (options?.limit) params.append('limit', options.limit.toString());
    if (options?.level) params.append('level', options.level);
    const query = params.toString();
    return apiClient.get<LogsResponse>(`/api/v2/system/logs${query ? `?${query}` : ''}`);
  },
};

// ============================================================================
// Authentication
// ============================================================================

export const authApi = {
  login: (credentials: LoginRequest) => 
    apiClient.post<AuthResponse>('/api/v1/auth/login', credentials),
  
  refresh: () => 
    apiClient.post<AuthResponse>('/api/v1/auth/refresh'),
  
  me: () => 
    apiClient.get<UserInfo>('/api/v1/auth/me'),
  
  logout: () => {
    apiClient.setToken(null);
    return Promise.resolve({ success: true, data: undefined });
  },
};

// ============================================================================
// Strategy Management
// ============================================================================

export const strategyApi = {
  list: () => 
    apiClient.get<{ strategies: StrategySummary[]; total: number }>('/api/v2/strategy'),
  
  get: (id: string) => 
    apiClient.get<StrategySummary>(`/api/v2/strategy/${id}`),
  
  start: (id: string, request: StrategyRequest) => 
    apiClient.post<{ id: string; status: string }>(`/api/v2/strategy`, { id, ...request }),
  
  stop: (id: string) => 
    apiClient.delete<{ success: boolean }>(`/api/v2/strategy/${id}`),
  
  pause: (id: string) => 
    apiClient.post<{ success: boolean }>(`/api/v2/strategy/${id}/pause`),
  
  resume: (id: string) => 
    apiClient.post<{ success: boolean }>(`/api/v2/strategy/${id}/resume`),
  
  getStats: (id: string) => 
    apiClient.get<StrategyStats>(`/api/v2/strategy/${id}/stats`),
};

// ============================================================================
// Backtest Management
// ============================================================================

export const backtestApi = {
  list: () => 
    apiClient.get<{ backtests: BacktestSummary[]; total: number }>('/api/v2/backtest'),
  
  run: (request: BacktestRequest) => 
    apiClient.post<{ id: string; status: string }>('/api/v2/backtest/run', request),
  
  get: (id: string) => 
    apiClient.get<BacktestResult>(`/api/v2/backtest/${id}`),
  
  getProgress: (id: string) => 
    apiClient.get<{ progress: number; status: string }>(`/api/v2/backtest/${id}/progress`),
  
  getResult: (id: string) => 
    apiClient.get<BacktestDetailedResult>(`/api/v2/backtest/${id}/result`),
  
  cancel: (id: string) => 
    apiClient.delete<{ success: boolean }>(`/api/v2/backtest/${id}`),
};

// ============================================================================
// Live Trading Management
// ============================================================================

export const liveApi = {
  list: () => 
    apiClient.get<{ sessions: LiveSummary[]; total: number }>('/api/v2/live'),
  
  get: (id: string) => 
    apiClient.get<LiveSummary>(`/api/v2/live/${id}`),
  
  start: (request: LiveRequest) => 
    apiClient.post<{ session_id: string; status: string }>('/api/v2/live', request),
  
  stop: (id: string) => 
    apiClient.delete<{ success: boolean }>(`/api/v2/live/${id}`),
  
  pause: (id: string) => 
    apiClient.post<{ success: boolean }>(`/api/v2/live/${id}/pause`),
  
  resume: (id: string) => 
    apiClient.post<{ success: boolean }>(`/api/v2/live/${id}/resume`),
  
  subscribe: (id: string, symbol: string) => 
    apiClient.post<{ success: boolean }>(`/api/v2/live/${id}/subscribe`, { symbol }),
  
  getStats: (id: string) => 
    apiClient.get<LiveStats>(`/api/v2/live/${id}/stats`),
};

// ============================================================================
// AI Configuration
// ============================================================================

export const aiApi = {
  getConfig: () => 
    apiClient.get<AIStatus>('/api/v2/ai/config'),
  
  updateConfig: (config: Partial<AIConfig>) => 
    apiClient.post<{ message: string }>('/api/v2/ai/config', config),
  
  enable: () => 
    apiClient.post<{ enabled: boolean; message: string }>('/api/v2/ai/enable'),
  
  disable: () => 
    apiClient.post<{ enabled: boolean; message: string }>('/api/v2/ai/disable'),
};

// ============================================================================
// Kill Switch
// ============================================================================

export const killSwitchApi = {
  activate: (reason: string, cancelOrders = true, closePositions = false) => 
    apiClient.post<KillSwitchResult>('/api/v2/system/kill-switch', {
      action: 'activate',
      reason,
      cancel_all_orders: cancelOrders,
      close_all_positions: closePositions,
    }),
  
  deactivate: () => 
    apiClient.post<{ kill_switch: boolean }>('/api/v2/system/kill-switch', {
      action: 'deactivate',
    }),
};

// ============================================================================
// Manager Stats
// ============================================================================

export const statsApi = {
  getManagerStats: () => 
    apiClient.get<ManagerStats>('/api/v2/system/stats'),
};

// Export all APIs
export const api = {
  health: healthApi,
  auth: authApi,
  strategy: strategyApi,
  backtest: backtestApi,
  live: liveApi,
  ai: aiApi,
  killSwitch: killSwitchApi,
  stats: statsApi,
  logs: logsApi,
};

export default api;
