import { Loader2, AlertCircle, Settings } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { getLoginUrl } from '@/api/client'
import type { OAuthStatus } from '@/types'

interface LoginScreenProps {
  authStatus: OAuthStatus | undefined
  isLoading: boolean
  error: Error | null
  onOpenSettings: () => void
}

export function LoginScreen({ authStatus, isLoading, error, onOpenSettings }: LoginScreenProps) {
  if (isLoading) {
    return (
      <div className="h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <Loader2 className="h-8 w-8 animate-spin mx-auto text-muted-foreground" />
          <p className="mt-4 text-muted-foreground">Checking authentication...</p>
        </div>
      </div>
    )
  }

  if (error) {
    const isCorsError = error.message === 'Failed to fetch' || error.message.includes('NetworkError')
    return (
      <div className="h-screen flex items-center justify-center bg-background">
        <div className="max-w-md mx-auto text-center p-8">
          <AlertCircle className="h-12 w-12 mx-auto text-destructive mb-4" />
          <h1 className="text-xl font-semibold mb-2">Connection Error</h1>
          <p className="text-muted-foreground mb-4">
            {isCorsError
              ? "Unable to connect to the backend. This may be a CORS configuration issue."
              : `Unable to connect to the backend server: ${error.message}`
            }
          </p>
          {isCorsError && (
            <p className="text-xs text-muted-foreground mb-6">
              Make sure CORS_ORIGINS is set on your backend to include this frontend's URL.
            </p>
          )}
          <Button onClick={onOpenSettings}>
            <Settings className="h-4 w-4 mr-2" />
            Open Settings
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="h-screen flex items-center justify-center bg-background">
      <div className="max-w-md mx-auto text-center p-8">
        <div className="mb-8">
          <h1 className="text-3xl font-bold mb-2">DataPoints</h1>
          <p className="text-muted-foreground">
            Sign in to access your feeds and articles
          </p>
        </div>

        {authStatus?.google_enabled && (
          <Button
            variant="outline"
            size="lg"
            className="w-full"
            onClick={() => window.location.href = getLoginUrl('google')}
          >
            <svg className="h-5 w-5 mr-3" viewBox="0 0 24 24">
              <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
              <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
              <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
              <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
            </svg>
            Continue with Google
          </Button>
        )}

        <div className="mt-8 pt-6 border-t border-border">
          <button
            onClick={onOpenSettings}
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            Configure backend settings
          </button>
        </div>
      </div>
    </div>
  )
}
