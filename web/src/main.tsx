import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

// Capture the OAuth token from the redirect URL BEFORE React/Query start, so the
// very first /auth/status request already carries it (no race with a useEffect).
function captureAuthToken() {
  try {
    const params = new URLSearchParams(window.location.search)
    const token = params.get('auth_token')
    if (token) {
      localStorage.setItem('authToken', token)
      window.history.replaceState({}, '', window.location.pathname)
    }
  } catch {
    /* ignore */
  }
}
captureAuthToken()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
