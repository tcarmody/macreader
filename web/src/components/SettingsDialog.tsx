import { useState, useEffect } from 'react'
import {
  X,
  Key,
  Server,
  Moon,
  Sun,
  Monitor,
  Check,
  AlertCircle,
  Loader2,
  LogOut,
  User,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { useAppStore, applyTheme } from '@/store/app-store'
import { useStatus, useAuthStatus, useLogout } from '@/hooks/use-queries'
import { getLoginUrl } from '@/api/client'
import type { ApiKeyConfig } from '@/types'

interface SettingsDialogProps {
  isOpen: boolean
  onClose: () => void
}

export function SettingsDialog({ isOpen, onClose }: SettingsDialogProps) {
  const { apiConfig, setApiConfig, theme, setTheme } = useAppStore()
  const { data: status, refetch: refetchStatus, isLoading: statusLoading } = useStatus()
  const { data: authStatus } = useAuthStatus()
  const logoutMutation = useLogout()

  const [localConfig, setLocalConfig] = useState<ApiKeyConfig>(apiConfig)
  const [testingConnection, setTestingConnection] = useState(false)
  const [_connectionStatus, setConnectionStatus] = useState<'idle' | 'success' | 'error'>('idle')
  const [activeTab, setActiveTab] = useState<'api' | 'appearance'>('api')

  useEffect(() => {
    setLocalConfig(apiConfig)
  }, [apiConfig, isOpen])

  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  if (!isOpen) return null

  const handleSave = () => {
    setApiConfig(localConfig)
    onClose()
  }

  const handleTestConnection = async () => {
    setTestingConnection(true)
    setConnectionStatus('idle')

    try {
      // Temporarily apply config for testing
      localStorage.setItem('apiConfig', JSON.stringify(localConfig))
      await refetchStatus()
      setConnectionStatus('success')
    } catch {
      setConnectionStatus('error')
    } finally {
      setTestingConnection(false)
      // Restore original config
      localStorage.setItem('apiConfig', JSON.stringify(apiConfig))
    }
  }

  // Utility function for masking keys (can be used for display)
  const _maskKey = (key: string | undefined) => {
    if (!key) return ''
    if (key.length <= 8) return '••••••••'
    return key.slice(0, 4) + '••••••••' + key.slice(-4)
  }
  void _maskKey // silence unused warning, available for future use

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50"
        onClick={onClose}
      />

      {/* Dialog */}
      <div className="relative bg-background border border-border rounded-lg shadow-xl w-full max-w-lg mx-4 max-h-[85vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border">
          <h2 className="text-lg font-semibold">Settings</h2>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-border">
          <button
            onClick={() => setActiveTab('api')}
            className={cn(
              "flex-1 px-4 py-2 text-sm font-medium transition-colors",
              activeTab === 'api'
                ? "border-b-2 border-primary text-primary"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            <Key className="h-4 w-4 inline mr-2" />
            API Keys
          </button>
          <button
            onClick={() => setActiveTab('appearance')}
            className={cn(
              "flex-1 px-4 py-2 text-sm font-medium transition-colors",
              activeTab === 'appearance'
                ? "border-b-2 border-primary text-primary"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            <Monitor className="h-4 w-4 inline mr-2" />
            Appearance
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4">
          {activeTab === 'api' && (
            <div className="space-y-6">
              {/* Backend URL */}
              <div>
                <label className="block text-sm font-medium mb-2">
                  <Server className="h-4 w-4 inline mr-2" />
                  Backend URL
                </label>
                <Input
                  value={localConfig.backendUrl}
                  onChange={(e) => setLocalConfig({ ...localConfig, backendUrl: e.target.value })}
                  placeholder="https://your-backend.railway.app"
                />
                <p className="text-xs text-muted-foreground mt-1">
                  The URL of your DataPoints backend server
                </p>
              </div>

              <Separator />

              {/* Connection Status */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium">Connection Status</span>
                  {statusLoading ? (
                    <Badge variant="secondary">
                      <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                      Checking...
                    </Badge>
                  ) : status ? (
                    <Badge variant="default" className="bg-green-500">
                      <Check className="h-3 w-3 mr-1" />
                      Connected
                    </Badge>
                  ) : (
                    <Badge variant="destructive">
                      <AlertCircle className="h-3 w-3 mr-1" />
                      Not Connected
                    </Badge>
                  )}
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleTestConnection}
                  disabled={testingConnection}
                >
                  {testingConnection ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    'Test Connection'
                  )}
                </Button>
              </div>

              {status && (
                <div className="text-sm text-muted-foreground bg-muted p-3 rounded-md">
                  <p>Provider: {status.provider || 'None'}</p>
                  <p>Model: {status.model || 'None'}</p>
                  <p>Summarization: {status.summarization_enabled ? 'Enabled' : 'Disabled'}</p>
                  <p>Authentication: {status.auth_enabled ? 'Required' : 'Disabled'}</p>
                </div>
              )}

              <Separator />

              {/* OAuth Login */}
              {authStatus?.enabled && (
                <>
                  <div>
                    <h3 className="text-sm font-medium mb-3">
                      <User className="h-4 w-4 inline mr-2" />
                      User Authentication
                    </h3>
                    {authStatus.user ? (
                      <div className="space-y-3">
                        <div className="flex items-center justify-between p-3 bg-muted rounded-md">
                          <div>
                            <p className="text-sm font-medium">{authStatus.user.name || authStatus.user.email}</p>
                            <p className="text-xs text-muted-foreground">{authStatus.user.email}</p>
                            <p className="text-xs text-muted-foreground capitalize">via {authStatus.user.provider}</p>
                          </div>
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => logoutMutation.mutate()}
                            disabled={logoutMutation.isPending}
                          >
                            <LogOut className="h-4 w-4 mr-1" />
                            Logout
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <div className="space-y-3">
                        <p className="text-xs text-muted-foreground">
                          Sign in to access this backend.
                        </p>
                        {authStatus.google_enabled && (
                          <Button
                            variant="outline"
                            onClick={() => window.location.href = getLoginUrl('google')}
                          >
                            <svg className="h-4 w-4 mr-2" viewBox="0 0 24 24">
                              <path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                              <path fill="currentColor" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                              <path fill="currentColor" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                              <path fill="currentColor" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                            </svg>
                            Google
                          </Button>
                        )}
                      </div>
                    )}
                  </div>
                  <Separator />
                </>
              )}

              {/* Auth API Key (fallback when OAuth not available) */}
              {status?.auth_enabled && !authStatus?.enabled && (
                <>
                  <div>
                    <h3 className="text-sm font-medium mb-3">Authentication</h3>
                    <p className="text-xs text-muted-foreground mb-4">
                      This backend requires an API key for access. Enter the key configured
                      in the server's AUTH_API_KEY environment variable.
                    </p>
                    <div>
                      <label className="block text-sm mb-1">API Key</label>
                      <Input
                        type="password"
                        value={localConfig.apiKey || ''}
                        onChange={(e) => setLocalConfig({ ...localConfig, apiKey: e.target.value })}
                        placeholder="Your API key"
                      />
                    </div>
                  </div>
                  <Separator />
                </>
              )}

              {/* API Keys */}
              <div>
                <h3 className="text-sm font-medium mb-3">LLM API Keys</h3>
                <p className="text-xs text-muted-foreground mb-4">
                  These keys are sent to your backend server for AI summarization.
                  They are stored in your browser's local storage.
                </p>

                <div className="space-y-4">
                  <div>
                    <label className="block text-sm mb-1">Anthropic API Key</label>
                    <Input
                      type="password"
                      value={localConfig.anthropicKey || ''}
                      onChange={(e) => setLocalConfig({ ...localConfig, anthropicKey: e.target.value })}
                      placeholder="sk-ant-..."
                    />
                  </div>

                  <div>
                    <label className="block text-sm mb-1">OpenAI API Key</label>
                    <Input
                      type="password"
                      value={localConfig.openaiKey || ''}
                      onChange={(e) => setLocalConfig({ ...localConfig, openaiKey: e.target.value })}
                      placeholder="sk-..."
                    />
                  </div>

                  <div>
                    <label className="block text-sm mb-1">Google AI API Key</label>
                    <Input
                      type="password"
                      value={localConfig.googleKey || ''}
                      onChange={(e) => setLocalConfig({ ...localConfig, googleKey: e.target.value })}
                      placeholder="AI..."
                    />
                  </div>

                  <div>
                    <label className="block text-sm mb-1">Preferred Provider</label>
                    <select
                      value={localConfig.preferredProvider || ''}
                      onChange={(e) => setLocalConfig({
                        ...localConfig,
                        preferredProvider: e.target.value as 'anthropic' | 'openai' | 'google' | undefined
                      })}
                      className="w-full h-10 px-3 rounded-md border border-input bg-background text-sm"
                    >
                      <option value="">Auto (first available)</option>
                      <option value="anthropic">Anthropic (Claude)</option>
                      <option value="openai">OpenAI (GPT)</option>
                      <option value="google">Google (Gemini)</option>
                    </select>
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'appearance' && (
            <div className="space-y-6">
              {/* Theme */}
              <div>
                <label className="block text-sm font-medium mb-3">Theme</label>
                <div className="grid grid-cols-3 gap-2">
                  <button
                    onClick={() => setTheme('light')}
                    className={cn(
                      "flex flex-col items-center gap-2 p-4 rounded-lg border transition-colors",
                      theme === 'light'
                        ? "border-primary bg-primary/5"
                        : "border-border hover:border-primary/50"
                    )}
                  >
                    <Sun className="h-5 w-5" />
                    <span className="text-sm">Light</span>
                  </button>
                  <button
                    onClick={() => setTheme('dark')}
                    className={cn(
                      "flex flex-col items-center gap-2 p-4 rounded-lg border transition-colors",
                      theme === 'dark'
                        ? "border-primary bg-primary/5"
                        : "border-border hover:border-primary/50"
                    )}
                  >
                    <Moon className="h-5 w-5" />
                    <span className="text-sm">Dark</span>
                  </button>
                  <button
                    onClick={() => setTheme('system')}
                    className={cn(
                      "flex flex-col items-center gap-2 p-4 rounded-lg border transition-colors",
                      theme === 'system'
                        ? "border-primary bg-primary/5"
                        : "border-border hover:border-primary/50"
                    )}
                  >
                    <Monitor className="h-5 w-5" />
                    <span className="text-sm">System</span>
                  </button>
                </div>
              </div>

              <Separator />

              {/* Keyboard Shortcuts Info */}
              <div>
                <h3 className="text-sm font-medium mb-3">Keyboard Shortcuts</h3>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Next article</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">j</kbd>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Previous article</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">k</kbd>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Toggle read</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">m</kbd>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Toggle bookmark</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">s</kbd>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Open in browser</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">o</kbd>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Refresh feeds</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">r</kbd>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Search</span>
                    <kbd className="px-2 py-1 bg-muted rounded text-xs">/</kbd>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-2 p-4 border-t border-border">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleSave}>
            Save Changes
          </Button>
        </div>
      </div>
    </div>
  )
}
