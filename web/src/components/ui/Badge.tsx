// ============================================================================
// Badge Component
// ============================================================================

import { cn } from '../../lib/utils';
import type { HTMLAttributes, ReactNode } from 'react';

interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  children: ReactNode;
  variant?: 'default' | 'success' | 'warning' | 'error' | 'info' | 'outline';
  size?: 'sm' | 'md' | 'lg';
  dot?: boolean;
}

export function Badge({ 
  children, 
  className, 
  variant = 'default',
  size = 'sm',
  dot = false,
  ...props 
}: BadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 font-medium rounded-full border',
        // Sizes
        size === 'sm' && 'px-2 py-0.5 text-xs',
        size === 'md' && 'px-2.5 py-1 text-sm',
        size === 'lg' && 'px-3 py-1.5 text-sm',
        // Variants
        variant === 'default' && 'bg-gray-500/10 text-gray-400 border-gray-500/20',
        variant === 'success' && 'bg-green-500/10 text-green-500 border-green-500/20',
        variant === 'warning' && 'bg-yellow-500/10 text-yellow-500 border-yellow-500/20',
        variant === 'error' && 'bg-red-500/10 text-red-500 border-red-500/20',
        variant === 'info' && 'bg-blue-500/10 text-blue-500 border-blue-500/20',
        variant === 'outline' && 'bg-transparent border-gray-600 text-gray-400',
        className
      )}
      {...props}
    >
      {dot && (
        <span 
          className={cn(
            'w-1.5 h-1.5 rounded-full',
            variant === 'default' && 'bg-gray-400',
            variant === 'success' && 'bg-green-500',
            variant === 'warning' && 'bg-yellow-500',
            variant === 'error' && 'bg-red-500',
            variant === 'info' && 'bg-blue-500',
            variant === 'outline' && 'bg-gray-400',
          )}
        />
      )}
      {children}
    </span>
  );
}

// Status Badge - a convenience wrapper for common status values
interface StatusBadgeProps extends Omit<BadgeProps, 'variant' | 'children'> {
  status: string;
  children?: ReactNode;
}

export function StatusBadge({ status, children, ...props }: StatusBadgeProps) {
  const getVariant = (): BadgeProps['variant'] => {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
      case 'completed':
      case 'success':
        return 'success';
      case 'paused':
      case 'pending':
      case 'waiting':
        return 'warning';
      case 'error':
      case 'failed':
      case 'stopped':
        return 'error';
      case 'starting':
      case 'stopping':
      case 'loading':
        return 'info';
      default:
        return 'default';
    }
  };

  // Capitalize first letter of status
  const displayText = children || status.charAt(0).toUpperCase() + status.slice(1).toLowerCase();

  return (
    <Badge variant={getVariant()} dot {...props}>
      {displayText}
    </Badge>
  );
}
