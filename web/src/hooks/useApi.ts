// ============================================================================
// React Query Hooks for API
// ============================================================================

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api';
import type {
  StrategyRequest,
  BacktestRequest,
  LiveRequest,
  AIConfig,
} from '../types/api';

// ============================================================================
// Query Keys
// ============================================================================

export const queryKeys = {
  health: ['health'] as const,
  systemHealth: ['system', 'health'] as const,
  strategies: ['strategies'] as const,
  strategy: (id: string) => ['strategies', id] as const,
  backtests: ['backtests'] as const,
  backtest: (id: string) => ['backtests', id] as const,
  liveSessions: ['live'] as const,
  liveSession: (id: string) => ['live', id] as const,
  aiConfig: ['ai', 'config'] as const,
};

// ============================================================================
// Health Queries
// ============================================================================

export function useHealth() {
  return useQuery({
    queryKey: queryKeys.health,
    queryFn: async () => {
      const result = await api.health.getHealth();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    refetchInterval: 30000, // Refetch every 30 seconds
  });
}

export function useSystemHealth() {
  return useQuery({
    queryKey: queryKeys.systemHealth,
    queryFn: async () => {
      const result = await api.health.getSystemHealth();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    refetchInterval: 5000, // Refetch every 5 seconds
  });
}

// ============================================================================
// Strategy Queries & Mutations
// ============================================================================

export function useStrategies() {
  return useQuery({
    queryKey: queryKeys.strategies,
    queryFn: async () => {
      const result = await api.strategy.list();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    refetchInterval: 5000,
  });
}

export function useStrategy(id: string) {
  return useQuery({
    queryKey: queryKeys.strategy(id),
    queryFn: async () => {
      const result = await api.strategy.get(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    enabled: !!id,
  });
}

export function useStartStrategy() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, request }: { id: string; request: StrategyRequest }) => {
      const result = await api.strategy.start(id, request);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.strategies });
    },
  });
}

export function useStopStrategy() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await api.strategy.stop(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.strategies });
    },
  });
}

export function usePauseStrategy() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await api.strategy.pause(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.strategies });
    },
  });
}

export function useResumeStrategy() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await api.strategy.resume(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.strategies });
    },
  });
}

// ============================================================================
// Backtest Queries & Mutations
// ============================================================================

export function useBacktests() {
  return useQuery({
    queryKey: queryKeys.backtests,
    queryFn: async () => {
      const result = await api.backtest.list();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    refetchInterval: 5000,
  });
}

export function useBacktest(id: string) {
  return useQuery({
    queryKey: queryKeys.backtest(id),
    queryFn: async () => {
      // First get the status
      const statusResult = await api.backtest.get(id);
      if (!statusResult.success) throw new Error(statusResult.error?.message);
      
      const status = statusResult.data!;
      
      // If completed, fetch the full result with trades and equity curve
      if (status.status === 'completed') {
        const resultData = await api.backtest.getResult(id);
        if (resultData.success && resultData.data) {
          return {
            ...status,
            ...resultData.data,
          };
        }
      }
      
      return status;
    },
    enabled: !!id,
    refetchInterval: (query) => {
      // Stop polling when backtest is complete
      const data = query.state.data;
      if (data?.status === 'completed' || data?.status === 'failed') {
        return false;
      }
      return 2000; // Poll every 2 seconds while running
    },
  });
}

// Hook to get detailed backtest result (with trades and equity curve)
export function useBacktestResult(id: string) {
  return useQuery({
    queryKey: [...queryKeys.backtest(id), 'result'] as const,
    queryFn: async () => {
      const result = await api.backtest.getResult(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    enabled: !!id,
  });
}

export function useRunBacktest() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (request: BacktestRequest) => {
      const result = await api.backtest.run(request);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.backtests });
    },
  });
}

export function useCancelBacktest() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await api.backtest.cancel(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.backtests });
    },
  });
}

// ============================================================================
// Live Trading Queries & Mutations
// ============================================================================

export function useLiveSessions() {
  return useQuery({
    queryKey: queryKeys.liveSessions,
    queryFn: async () => {
      const result = await api.live.list();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    refetchInterval: 5000,
  });
}

export function useLiveSession(id: string) {
  return useQuery({
    queryKey: queryKeys.liveSession(id),
    queryFn: async () => {
      const result = await api.live.get(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    enabled: !!id,
  });
}

export function useStartLiveSession() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (request: LiveRequest) => {
      const result = await api.live.start(request);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.liveSessions });
    },
  });
}

export function useStopLiveSession() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await api.live.stop(id);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.liveSessions });
    },
  });
}

// ============================================================================
// AI Configuration Queries & Mutations
// ============================================================================

export function useAIConfig() {
  return useQuery({
    queryKey: queryKeys.aiConfig,
    queryFn: async () => {
      const result = await api.ai.getConfig();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
  });
}

export function useUpdateAIConfig() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (config: Partial<AIConfig>) => {
      const result = await api.ai.updateConfig(config);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.aiConfig });
    },
  });
}

export function useEnableAI() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async () => {
      const result = await api.ai.enable();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.aiConfig });
    },
  });
}

export function useDisableAI() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async () => {
      const result = await api.ai.disable();
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.aiConfig });
    },
  });
}

// ============================================================================
// Kill Switch Mutation
// ============================================================================

export function useKillSwitch() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ reason, cancelOrders, closePositions }: { 
      reason: string; 
      cancelOrders?: boolean; 
      closePositions?: boolean;
    }) => {
      const result = await api.killSwitch.activate(reason, cancelOrders, closePositions);
      if (!result.success) throw new Error(result.error?.message);
      return result.data!;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.strategies });
      queryClient.invalidateQueries({ queryKey: queryKeys.liveSessions });
      queryClient.invalidateQueries({ queryKey: queryKeys.systemHealth });
    },
  });
}
