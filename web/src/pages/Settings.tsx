// ============================================================================
// Settings Page
// ============================================================================

import { 
  Settings as SettingsIcon, 
  Moon, 
  Sun, 
  Bell, 
  Shield,
  Database,
  Wifi,
  Save
} from 'lucide-react';
import { useAppStore } from '../stores/app';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { Select, OptionCard } from '../components/ui/Select';

export default function Settings() {
  const { theme, setTheme } = useAppStore();

  return (
    <div className="space-y-6 max-w-4xl">
      {/* Page Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Settings</h1>
        <p className="text-gray-400 mt-1">Configure your trading dashboard</p>
      </div>

      {/* Appearance */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Sun className="w-5 h-5" />
            Appearance
          </CardTitle>
          <CardDescription>Customize the look and feel</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <OptionCard
              selected={theme === 'dark'}
              onSelect={() => setTheme('dark')}
              icon={<Moon className="w-5 h-5" />}
              title="Dark"
              description="Dark theme"
            />
            <OptionCard
              selected={theme === 'light'}
              onSelect={() => setTheme('light')}
              icon={<Sun className="w-5 h-5" />}
              title="Light"
              description="Light theme"
            />
            <OptionCard
              selected={theme === 'system'}
              onSelect={() => setTheme('system')}
              icon={<SettingsIcon className="w-5 h-5" />}
              title="System"
              description="Follow system"
            />
          </div>
        </CardContent>
      </Card>

      {/* Connection Settings */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Wifi className="w-5 h-5" />
            Connection
          </CardTitle>
          <CardDescription>API and WebSocket settings</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <Input
              label="API URL"
              type="url"
              defaultValue="http://localhost:8080"
              hint="The URL of your zigQuant backend server"
            />
            <Input
              label="WebSocket URL"
              type="url"
              defaultValue="ws://localhost:8080/ws"
              hint="WebSocket endpoint for real-time updates"
            />
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Auto-reconnect</p>
                <p className="text-sm text-gray-500">Automatically reconnect on connection loss</p>
              </div>
              <Button size="sm" variant="outline">Enabled</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Notifications */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Bell className="w-5 h-5" />
            Notifications
          </CardTitle>
          <CardDescription>Configure alerts and notifications</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Trade Alerts</p>
                <p className="text-sm text-gray-500">Notify when trades are executed</p>
              </div>
              <Button size="sm" variant="outline">Enabled</Button>
            </div>
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Error Alerts</p>
                <p className="text-sm text-gray-500">Notify on strategy errors</p>
              </div>
              <Button size="sm" variant="outline">Enabled</Button>
            </div>
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">PnL Alerts</p>
                <p className="text-sm text-gray-500">Notify on significant PnL changes</p>
              </div>
              <Button size="sm" variant="outline">Disabled</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Security */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Shield className="w-5 h-5" />
            Security
          </CardTitle>
          <CardDescription>Authentication and security settings</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <Input
              label="API Key"
              type="password"
              placeholder="Enter API key"
              hint="Used for authenticating with the backend"
            />
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Session Timeout</p>
                <p className="text-sm text-gray-500">Auto logout after inactivity</p>
              </div>
              <Select
                options={[
                  { value: '15', label: '15 minutes' },
                  { value: '30', label: '30 minutes' },
                  { value: '60', label: '1 hour' },
                  { value: '0', label: 'Never' },
                ]}
                defaultValue="30"
                className="w-40"
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Data & Storage */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="w-5 h-5" />
            Data & Storage
          </CardTitle>
          <CardDescription>Manage local data and cache</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Clear Cache</p>
                <p className="text-sm text-gray-500">Remove cached data from browser</p>
              </div>
              <Button size="sm" variant="outline">Clear</Button>
            </div>
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Export Settings</p>
                <p className="text-sm text-gray-500">Download your settings as JSON</p>
              </div>
              <Button size="sm" variant="outline">Export</Button>
            </div>
            <div className="flex items-center justify-between py-2">
              <div>
                <p className="text-white font-medium">Reset to Defaults</p>
                <p className="text-sm text-gray-500">Restore all settings to defaults</p>
              </div>
              <Button size="sm" variant="danger">Reset</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Save Button */}
      <div className="flex justify-end">
        <Button icon={<Save className="w-4 h-4" />}>
          Save All Settings
        </Button>
      </div>
    </div>
  );
}
