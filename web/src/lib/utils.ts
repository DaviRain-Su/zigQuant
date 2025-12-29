// ============================================================================
// Utility Functions
// ============================================================================

import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

// ============================================================================
// Class Name Utilities
// ============================================================================

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// ============================================================================
// Number Formatting
// ============================================================================

export function formatNumber(
  value: number,
  options: Intl.NumberFormatOptions = {}
): string {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    ...options,
  }).format(value);
}

export function formatCurrency(
  value: number,
  currency = 'USD'
): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatPercent(value: number, decimals = 2): string {
  return `${(value * 100).toFixed(decimals)}%`;
}

export function formatCompactNumber(value: number): string {
  return new Intl.NumberFormat('en-US', {
    notation: 'compact',
    compactDisplay: 'short',
  }).format(value);
}

// ============================================================================
// PnL Formatting
// ============================================================================

export function formatPnL(value: number): string {
  const prefix = value >= 0 ? '+' : '';
  return `${prefix}${formatCurrency(value)}`;
}

export function getPnLColor(value: number): string {
  if (value > 0) return 'text-green-500';
  if (value < 0) return 'text-red-500';
  return 'text-gray-500';
}

// ============================================================================
// Time Formatting
// ============================================================================

export function formatDuration(seconds: number): string {
  if (seconds < 60) {
    return `${seconds}s`;
  }
  
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    const secs = seconds % 60;
    return `${minutes}m ${secs}s`;
  }
  
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    const mins = minutes % 60;
    return `${hours}h ${mins}m`;
  }
  
  const days = Math.floor(hours / 24);
  const hrs = hours % 24;
  return `${days}d ${hrs}h`;
}

export function formatTimestamp(timestamp: number): string {
  return new Date(timestamp).toLocaleString();
}

export function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = now - timestamp;
  
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return 'just now';
  
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  
  return formatTimestamp(timestamp);
}

// ============================================================================
// Status Utilities
// ============================================================================

export type StatusType = 'running' | 'stopped' | 'paused' | 'error' | 'pending' | 'starting' | 'stopping';

export function getStatusColor(status: StatusType): string {
  switch (status) {
    case 'running':
      return 'bg-green-500/10 text-green-500 border-green-500/20';
    case 'stopped':
      return 'bg-gray-500/10 text-gray-500 border-gray-500/20';
    case 'paused':
      return 'bg-yellow-500/10 text-yellow-500 border-yellow-500/20';
    case 'error':
      return 'bg-red-500/10 text-red-500 border-red-500/20';
    case 'pending':
    case 'starting':
    case 'stopping':
      return 'bg-blue-500/10 text-blue-500 border-blue-500/20';
    default:
      return 'bg-gray-500/10 text-gray-500 border-gray-500/20';
  }
}

export function getStatusDot(status: StatusType): string {
  switch (status) {
    case 'running':
      return 'bg-green-500';
    case 'stopped':
      return 'bg-gray-500';
    case 'paused':
      return 'bg-yellow-500';
    case 'error':
      return 'bg-red-500';
    case 'pending':
    case 'starting':
    case 'stopping':
      return 'bg-blue-500 animate-pulse';
    default:
      return 'bg-gray-500';
  }
}

// ============================================================================
// Validation Utilities
// ============================================================================

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function isValidSymbol(symbol: string): boolean {
  return /^[A-Z]{2,10}(-[A-Z]{2,10})?$/.test(symbol.toUpperCase());
}

// ============================================================================
// Debounce / Throttle
// ============================================================================

export function debounce<T extends (...args: unknown[]) => unknown>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
}

export function throttle<T extends (...args: unknown[]) => unknown>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let lastCall = 0;
  return (...args: Parameters<T>) => {
    const now = Date.now();
    if (now - lastCall >= delay) {
      lastCall = now;
      fn(...args);
    }
  };
}
