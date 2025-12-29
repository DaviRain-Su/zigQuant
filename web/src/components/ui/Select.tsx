// ============================================================================
// Select Component
// ============================================================================

import { cn } from '../../lib/utils';
import { ChevronDown } from 'lucide-react';
import { forwardRef, type SelectHTMLAttributes, type ReactNode } from 'react';

interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

interface SelectProps extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'children'> {
  label?: string;
  error?: string;
  hint?: string;
  options: SelectOption[];
  placeholder?: string;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, label, error, hint, options, placeholder, ...props }, ref) => {
    return (
      <div className="space-y-1.5">
        {label && (
          <label className="block text-sm font-medium text-gray-300">
            {label}
          </label>
        )}
        <div className="relative">
          <select
            ref={ref}
            className={cn(
              'w-full appearance-none rounded-lg border bg-gray-800 text-white',
              'focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              'transition-colors duration-200',
              error ? 'border-red-500' : 'border-gray-700',
              'pl-4 pr-10 py-2.5',
              className
            )}
            {...props}
          >
            {placeholder && (
              <option value="" disabled>
                {placeholder}
              </option>
            )}
            {options.map((option) => (
              <option 
                key={option.value} 
                value={option.value}
                disabled={option.disabled}
              >
                {option.label}
              </option>
            ))}
          </select>
          <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" />
        </div>
        {error && (
          <p className="text-sm text-red-500">{error}</p>
        )}
        {hint && !error && (
          <p className="text-sm text-gray-500">{hint}</p>
        )}
      </div>
    );
  }
);

Select.displayName = 'Select';

// Multi-select option card
interface OptionCardProps {
  selected: boolean;
  onSelect: () => void;
  icon?: ReactNode;
  title: string;
  description?: string;
  disabled?: boolean;
}

export function OptionCard({ 
  selected, 
  onSelect, 
  icon, 
  title, 
  description,
  disabled 
}: OptionCardProps) {
  return (
    <button
      type="button"
      onClick={onSelect}
      disabled={disabled}
      className={cn(
        'w-full p-4 rounded-lg border text-left transition-all duration-200',
        'focus:outline-none focus:ring-2 focus:ring-blue-500',
        selected 
          ? 'border-blue-500 bg-blue-500/10' 
          : 'border-gray-700 bg-gray-800/50 hover:border-gray-600',
        disabled && 'opacity-50 cursor-not-allowed'
      )}
    >
      <div className="flex items-start gap-3">
        {icon && (
          <div className={cn(
            'p-2 rounded-lg',
            selected ? 'bg-blue-500/20 text-blue-500' : 'bg-gray-700 text-gray-400'
          )}>
            {icon}
          </div>
        )}
        <div>
          <p className={cn(
            'font-medium',
            selected ? 'text-white' : 'text-gray-300'
          )}>
            {title}
          </p>
          {description && (
            <p className="text-sm text-gray-500 mt-0.5">{description}</p>
          )}
        </div>
      </div>
    </button>
  );
}
