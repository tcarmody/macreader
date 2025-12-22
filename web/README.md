# DataPoints Web PWA

A Progressive Web App (PWA) frontend for the DataPoints RSS reader, built with React, Vite, and Tailwind CSS.

## Features

- **Three-pane layout**: Sidebar, article list, and article detail view
- **RSS feed management**: Add, organize, and refresh feeds
- **AI-powered summarization**: Generate summaries using Anthropic, OpenAI, or Google AI
- **Library**: Save URLs and upload documents (PDF, DOCX, TXT, MD)
- **Keyboard shortcuts**: Vim-style navigation (j/k, m, s, o, r, /)
- **Dark/light theme**: System preference or manual selection
- **PWA support**: Install as a standalone app on any platform
- **Offline capable**: Service worker caches static assets

## Quick Start

### Prerequisites

- Node.js 18+
- A running DataPoints backend server

### Development

```bash
# Install dependencies
npm install

# Start development server (proxies /api to localhost:5005)
npm run dev
```

The app will be available at http://localhost:3000

### Production Build

```bash
npm run build
npm run preview
```

## Deployment

### Frontend (Vercel)

1. **Connect your repository** to Vercel
2. **Set the root directory** to `web`
3. **Add environment variable**:
   - `VITE_API_URL`: Your backend URL (e.g., `https://your-backend.railway.app`)
4. **Deploy**

Vercel will automatically detect Vite and configure the build.

### Backend (Railway)

1. **Create a new project** on Railway
2. **Connect your repository**
3. **Add environment variables**:
   - `ANTHROPIC_API_KEY` (or OpenAI/Google key)
   - `CORS_ORIGINS`: Your Vercel frontend URL
4. **Deploy**

Railway will use the `Procfile` to start the backend.

## Configuration

### API Keys

Users provide their own LLM API keys through the Settings page. Keys are:
- Stored in browser localStorage
- Sent to backend via headers
- Never logged or persisted on the server

### Environment Variables

**Frontend** (`web/.env.local`):
```env
VITE_API_URL=https://your-backend.railway.app
```

**Backend** (`.env` or Railway dashboard):
```env
# At least one LLM key for summarization
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GOOGLE_API_KEY=AI...

# CORS origins (comma-separated)
CORS_ORIGINS=https://your-app.vercel.app

# Server config
PORT=5005
LOG_LEVEL=INFO
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` | Next article |
| `k` | Previous article |
| `m` | Toggle read/unread |
| `s` | Toggle bookmark |
| `o` | Open in browser |
| `r` | Refresh feeds |
| `/` | Focus search |
| `Esc` | Clear search |
| `Cmd/Ctrl+,` | Open settings |
| `Cmd/Ctrl+n` | Add feed |

## Tech Stack

- **Framework**: React 18 + TypeScript
- **Build**: Vite
- **Styling**: Tailwind CSS + shadcn/ui patterns
- **State**: Zustand + TanStack Query
- **PWA**: vite-plugin-pwa

## Project Structure

```
web/
├── src/
│   ├── api/          # API client
│   ├── components/   # React components
│   │   └── ui/       # Base UI components
│   ├── hooks/        # Custom hooks
│   ├── lib/          # Utilities
│   ├── store/        # Zustand store
│   ├── types/        # TypeScript types
│   ├── App.tsx       # Main app component
│   └── main.tsx      # Entry point
├── public/           # Static assets
└── vite.config.ts    # Vite config
```
