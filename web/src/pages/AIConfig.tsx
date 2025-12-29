// ============================================================================
// AI Configuration Page
// ============================================================================

import { useState } from 'react';
import { 
  Brain, 
  Power, 
  Settings, 
  CheckCircle,
  XCircle,
  Loader2,
  Sparkles
} from 'lucide-react';
import { useAIConfig, useEnableAI, useDisableAI, useUpdateAIConfig } from '../hooks/useApi';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { Badge } from '../components/ui/Badge';
import { Input } from '../components/ui/Input';
import { Select, OptionCard } from '../components/ui/Select';

export default function AIConfig() {
  const { data: aiStatus, isLoading } = useAIConfig();
  const enableAI = useEnableAI();
  const disableAI = useDisableAI();
  const updateConfig = useUpdateAIConfig();

  const [provider, setProvider] = useState(aiStatus?.provider || 'openai');
  const [model, setModel] = useState(aiStatus?.model_id || 'gpt-4');
  const [apiKey, setApiKey] = useState('');

  const handleToggle = async () => {
    try {
      if (aiStatus?.enabled) {
        await disableAI.mutateAsync();
      } else {
        await enableAI.mutateAsync();
      }
    } catch (err) {
      console.error('Failed to toggle AI:', err);
    }
  };

  const handleSaveConfig = async () => {
    try {
      await updateConfig.mutateAsync({
        provider,
        model_id: model,
        api_key: apiKey || undefined,
      });
    } catch (err) {
      console.error('Failed to update config:', err);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="w-8 h-8 animate-spin text-gray-500" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-4xl">
      {/* Page Header */}
      <div>
        <h1 className="text-2xl font-bold text-white">AI Configuration</h1>
        <p className="text-gray-400 mt-1">Configure AI-powered trading assistance</p>
      </div>

      {/* AI Status Card */}
      <Card>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className={`p-3 rounded-xl ${aiStatus?.enabled ? 'bg-purple-500/10' : 'bg-gray-800'}`}>
              <Brain className={`w-8 h-8 ${aiStatus?.enabled ? 'text-purple-500' : 'text-gray-500'}`} />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-white">AI Assistant</h2>
              <div className="flex items-center gap-2 mt-1">
                {aiStatus?.enabled ? (
                  <>
                    <CheckCircle className="w-4 h-4 text-green-500" />
                    <span className="text-green-500">Active</span>
                  </>
                ) : (
                  <>
                    <XCircle className="w-4 h-4 text-gray-500" />
                    <span className="text-gray-500">Disabled</span>
                  </>
                )}
                {aiStatus?.provider && (
                  <Badge variant="outline" className="ml-2">
                    {aiStatus.provider}
                  </Badge>
                )}
              </div>
            </div>
          </div>
          <Button
            variant={aiStatus?.enabled ? 'danger' : 'success'}
            onClick={handleToggle}
            loading={enableAI.isPending || disableAI.isPending}
            icon={<Power className="w-4 h-4" />}
          >
            {aiStatus?.enabled ? 'Disable' : 'Enable'}
          </Button>
        </div>
      </Card>

      {/* Provider Selection */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Sparkles className="w-5 h-5" />
            Provider
          </CardTitle>
          <CardDescription>Choose your AI provider</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <OptionCard
              selected={provider === 'openai'}
              onSelect={() => setProvider('openai')}
              title="OpenAI"
              description="GPT-4, GPT-3.5 Turbo"
            />
            <OptionCard
              selected={provider === 'anthropic'}
              onSelect={() => setProvider('anthropic')}
              title="Anthropic"
              description="Claude 3, Claude 2"
            />
            <OptionCard
              selected={provider === 'local'}
              onSelect={() => setProvider('local')}
              title="Local"
              description="Ollama, LM Studio"
            />
          </div>
        </CardContent>
      </Card>

      {/* Model Configuration */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Settings className="w-5 h-5" />
            Model Settings
          </CardTitle>
          <CardDescription>Configure model parameters</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <Select
              label="Model"
              value={model}
              onChange={(e) => setModel(e.target.value)}
              options={
                provider === 'openai' 
                  ? [
                      { value: 'gpt-4', label: 'GPT-4' },
                      { value: 'gpt-4-turbo', label: 'GPT-4 Turbo' },
                      { value: 'gpt-3.5-turbo', label: 'GPT-3.5 Turbo' },
                    ]
                  : provider === 'anthropic'
                  ? [
                      { value: 'claude-3-opus', label: 'Claude 3 Opus' },
                      { value: 'claude-3-sonnet', label: 'Claude 3 Sonnet' },
                      { value: 'claude-3-haiku', label: 'Claude 3 Haiku' },
                    ]
                  : [
                      { value: 'llama2', label: 'Llama 2' },
                      { value: 'mistral', label: 'Mistral' },
                      { value: 'codellama', label: 'Code Llama' },
                    ]
              }
            />

            <Input
              label="API Key"
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="Enter your API key"
              hint="Your API key is stored securely and never shared"
            />

            {provider === 'local' && (
              <Input
                label="Base URL"
                type="url"
                placeholder="http://localhost:11434"
                hint="URL of your local LLM server"
              />
            )}
          </div>

          <div className="mt-6 pt-4 border-t border-gray-800 flex justify-end">
            <Button
              onClick={handleSaveConfig}
              loading={updateConfig.isPending}
            >
              Save Configuration
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* AI Features */}
      <Card>
        <CardHeader>
          <CardTitle>AI Features</CardTitle>
          <CardDescription>Available AI-powered capabilities</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 bg-gray-800/50 rounded-lg">
              <h3 className="font-medium text-white">Strategy Analysis</h3>
              <p className="text-sm text-gray-500 mt-1">
                AI analyzes market conditions and provides strategy recommendations
              </p>
            </div>
            <div className="p-4 bg-gray-800/50 rounded-lg">
              <h3 className="font-medium text-white">Risk Assessment</h3>
              <p className="text-sm text-gray-500 mt-1">
                Automated risk evaluation for trades and portfolio positions
              </p>
            </div>
            <div className="p-4 bg-gray-800/50 rounded-lg">
              <h3 className="font-medium text-white">Market Insights</h3>
              <p className="text-sm text-gray-500 mt-1">
                Real-time market analysis and trend identification
              </p>
            </div>
            <div className="p-4 bg-gray-800/50 rounded-lg">
              <h3 className="font-medium text-white">Trade Optimization</h3>
              <p className="text-sm text-gray-500 mt-1">
                AI-powered parameter optimization for better performance
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
