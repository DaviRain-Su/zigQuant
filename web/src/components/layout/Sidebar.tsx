// ============================================================================
// Sidebar Component
// ============================================================================

import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  Play,
  History,
  Bot,
  Settings,
  AlertTriangle,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { cn } from '../../lib/utils';
import { useAppStore } from '../../stores/app';

const navigation = [
  { name: 'Dashboard', href: '/', icon: LayoutDashboard },
  { name: 'Trading', href: '/live', icon: Play },
  { name: 'Backtests', href: '/backtests', icon: History },
  { name: 'AI Config', href: '/ai', icon: Bot },
  { name: 'Settings', href: '/settings', icon: Settings },
];

export function Sidebar() {
  const location = useLocation();
  const { sidebarCollapsed, toggleSidebar, killSwitchActive } = useAppStore();

  return (
    <aside
      className={cn(
        'flex flex-col bg-gray-900 border-r border-gray-800 transition-all duration-300',
        sidebarCollapsed ? 'w-16' : 'w-64'
      )}
    >
      {/* Logo */}
      <div className="flex items-center h-16 px-4 border-b border-gray-800">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-sm">ZQ</span>
          </div>
          {!sidebarCollapsed && (
            <span className="text-white font-semibold text-lg">zigQuant</span>
          )}
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-4 space-y-1">
        {navigation.map((item) => {
          const isActive = location.pathname === item.href;
          return (
            <Link
              key={item.name}
              to={item.href}
              className={cn(
                'flex items-center gap-3 px-3 py-2 rounded-lg transition-colors',
                isActive
                  ? 'bg-blue-600/10 text-blue-400'
                  : 'text-gray-400 hover:text-white hover:bg-gray-800'
              )}
            >
              <item.icon className="w-5 h-5 flex-shrink-0" />
              {!sidebarCollapsed && <span>{item.name}</span>}
            </Link>
          );
        })}
      </nav>

      {/* Kill Switch Warning */}
      {killSwitchActive && (
        <div className="mx-4 mb-4 p-3 bg-red-500/10 border border-red-500/20 rounded-lg">
          <div className="flex items-center gap-2 text-red-500">
            <AlertTriangle className="w-4 h-4" />
            {!sidebarCollapsed && (
              <span className="text-sm font-medium">Kill Switch Active</span>
            )}
          </div>
        </div>
      )}

      {/* Collapse Button */}
      <div className="p-4 border-t border-gray-800">
        <button
          onClick={toggleSidebar}
          className="flex items-center justify-center w-full p-2 text-gray-400 hover:text-white hover:bg-gray-800 rounded-lg transition-colors"
        >
          {sidebarCollapsed ? (
            <ChevronRight className="w-5 h-5" />
          ) : (
            <>
              <ChevronLeft className="w-5 h-5" />
              <span className="ml-2">Collapse</span>
            </>
          )}
        </button>
      </div>
    </aside>
  );
}

export default Sidebar;
