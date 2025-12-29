// ============================================================================
// Button Component
// ============================================================================

import { cn } from '../../lib/utils';
import { Loader2 } from 'lucide-react';
import type { ButtonHTMLAttributes, ReactNode } from 'react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger' | 'success' | 'outline';
  size?: 'sm' | 'md' | 'lg' | 'icon';
  loading?: boolean;
  icon?: ReactNode;
}

export function Button({ 
  children, 
  className, 
  variant = 'primary',
  size = 'md',
  loading = false,
  disabled,
  icon,
  ...props 
}: ButtonProps) {
  const isDisabled = disabled || loading;

  return (
    <button
      className={cn(
        'inline-flex items-center justify-center gap-2 font-medium rounded-lg transition-all duration-200',
        'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-gray-900',
        'disabled:opacity-50 disabled:cursor-not-allowed',
        // Variants
        variant === 'primary' && [
          'bg-blue-600 text-white',
          'hover:bg-blue-700 focus:ring-blue-500',
        ],
        variant === 'secondary' && [
          'bg-gray-700 text-white',
          'hover:bg-gray-600 focus:ring-gray-500',
        ],
        variant === 'ghost' && [
          'bg-transparent text-gray-400',
          'hover:bg-gray-800 hover:text-white focus:ring-gray-500',
        ],
        variant === 'danger' && [
          'bg-red-600 text-white',
          'hover:bg-red-700 focus:ring-red-500',
        ],
        variant === 'success' && [
          'bg-green-600 text-white',
          'hover:bg-green-700 focus:ring-green-500',
        ],
        variant === 'outline' && [
          'border border-gray-600 bg-transparent text-gray-300',
          'hover:bg-gray-800 hover:border-gray-500 focus:ring-gray-500',
        ],
        // Sizes
        size === 'sm' && 'px-3 py-1.5 text-sm',
        size === 'md' && 'px-4 py-2 text-sm',
        size === 'lg' && 'px-6 py-3 text-base',
        size === 'icon' && 'p-2',
        className
      )}
      disabled={isDisabled}
      {...props}
    >
      {loading ? (
        <Loader2 className="w-4 h-4 animate-spin" />
      ) : icon ? (
        icon
      ) : null}
      {children}
    </button>
  );
}

// Icon Button - convenience wrapper
interface IconButtonProps extends Omit<ButtonProps, 'children' | 'size'> {
  icon: ReactNode;
  label: string;
}

export function IconButton({ icon, label, className, ...props }: IconButtonProps) {
  return (
    <Button 
      size="icon" 
      variant="ghost" 
      className={cn('rounded-full', className)}
      aria-label={label}
      {...props}
    >
      {icon}
    </Button>
  );
}
