# DataPoints

A modern RSS reader with AI-powered summarization, available as a native macOS app and Progressive Web App.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Python](https://img.shields.io/badge/Python-3.11%2B-green)
![React](https://img.shields.io/badge/React-18-61DAFB)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

## Features

### Core
- **RSS Feed Management** - Subscribe to feeds, organize by category, import/export OPML
- **AI Summarization** - Automatic article summaries with key points extraction
- **Multi-Provider LLM Support** - Choose between Anthropic Claude, OpenAI GPT, or Google Gemini
- **Library** - Save URLs and upload documents (PDF, DOCX, TXT) for summarization
- **Full-Text Search** - Fast search across all articles with SQLite FTS5
- **Multi-User Support** - Per-user read/bookmark state and library items with OAuth

### Reading Experience
- **Article Themes (macOS)** - 7 reading themes: Auto, Manuscript, Noir, Ember, Forest, Ocean, Midnight
- **Design Styles (Web)** - 9 visual variants including accessibility-focused High Contrast, Sepia, and Mono
- **Typography Options (macOS)** - 28 fonts across sans-serif, serif, slab-serif, and monospace families
- **Article Organization** - Group by date/feed/topic, sort options, hide read articles toggle
- **Infinite Scroll** - Paginated article loading for large feeds

### Analytics
- **Reading Statistics** - Track articles read, reading time, bookmarks, and top feeds
- **Summarization Metrics** - Articles summarized, rate, model usage breakdown
- **Topic Trends** - AI-powered topic clustering with historical trend analysis

### Platform
- **Native macOS App** - SwiftUI interface with Keychain, Spotlight, and notification integration
- **Web PWA** - Cross-platform Progressive Web App with offline support and keyboard shortcuts
- **Security** - API key auth, OAuth login (Google/GitHub), rate limiting, SSRF protection

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│            macOS SwiftUI App  /  Web React PWA              │
│  ┌─────────┐  ┌─────────────┐  ┌──────────────────────────┐ │
│  │ Sidebar │  │ Article List│  │     Article Detail       │ │
│  │ (Feeds) │  │ (Grouped)   │  │  (Content + AI Summary)  │ │
│  └─────────┘  └─────────────┘  └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Python FastAPI Backend                     │
│  ┌──────────┐  ┌────────────┐  ┌─────────────────────────┐  │
│  │ Feed     │  │ Article    │  │    LLM Providers        │  │
│  │ Parser   │  │ Summarizer │  │  (Claude/GPT/Gemini)    │  │
│  └──────────┘  └────────────┘  └─────────────────────────┘  │
│                      │                                       │
│                      ▼                                       │
│              ┌──────────────┐                               │
│              │   SQLite DB  │                               │
│              │   (+ FTS5)   │                               │
│              └──────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option 1: Local Development

```bash
# Clone the repository
git clone https://github.com/yourusername/macreader.git
cd macreader

# Create and activate virtual environment
python3 -m venv rss_venv
source rss_venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create .env file with your API key
cp .env.example .env
# Edit .env with your API keys

# Start the backend
make run
```

The backend runs on `http://localhost:5005`.

### Option 2: Cloud Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for deploying to Railway (backend) and Vercel (frontend).

## Clients

### macOS App

```bash
cd app/DataPointsAI
open DataPointsAI.xcodeproj
```

Build and run from Xcode. On first launch, configure API keys via the setup wizard.

### Web PWA

```bash
cd web
npm install
npm run dev
```

The web app runs on `http://localhost:3000` and proxies API requests to the backend.

## Configuration

Create a `.env` file from `.env.example`:

```bash
# LLM Provider (at least one required)
ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
# GOOGLE_API_KEY=AI...

# Server settings
PORT=5005
LOG_LEVEL=INFO

# Authentication (choose one or both)
# AUTH_API_KEY=your-secret-key   # Simple API key auth
# See DEPLOYMENT.md for OAuth setup (Google/GitHub login)

# Advanced features (optional)
ENABLE_JS_RENDER=true       # JavaScript rendering for dynamic content
ENABLE_ARCHIVE=true         # Archive service for paywalled content
```

## Security

DataPoints supports multiple authentication methods for production deployment:

- **No Auth** - Default for local development
- **API Key** - Simple shared key via `AUTH_API_KEY` environment variable
- **OAuth** - User login via Google and/or GitHub (recommended for multi-user)
- **Both** - API key for programmatic access + OAuth for user login

Additional security features:
- **Rate Limiting** - Configurable requests per minute per IP
- **SSRF Protection** - Blocks requests to private networks and cloud metadata
- **CORS** - Configurable allowed origins for cross-origin requests

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed security configuration.

## Project Structure

```
macreader/
├── app/                    # macOS SwiftUI application
│   └── DataPointsAI/
├── backend/                # Python FastAPI server
│   ├── routes/             # API endpoints
│   ├── providers/          # LLM provider integrations
│   ├── advanced/           # JS rendering, archive fallbacks
│   └── tests/              # Test suite
├── web/                    # React PWA frontend
│   ├── src/
│   │   ├── api/            # API client
│   │   ├── components/     # React components
│   │   ├── hooks/          # Custom hooks
│   │   └── store/          # Zustand state
│   └── public/
├── data/                   # SQLite database (local)
├── DEPLOYMENT.md           # Cloud deployment guide
├── DOCTRINE.md             # Architecture decisions
└── SUMMARIZATION_PROMPTS.md  # AI prompt engineering
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /articles` | List articles with filtering |
| `POST /articles/{id}/summarize` | Trigger AI summarization |
| `GET /feeds` | List subscribed feeds |
| `POST /feeds` | Subscribe to a new feed |
| `POST /feeds/refresh` | Refresh all feeds |
| `POST /feeds/import-opml` | Import OPML |
| `GET /feeds/export-opml` | Export OPML |
| `GET /standalone` | List library items |
| `POST /standalone/url` | Add URL to library |
| `GET /search` | Full-text search |
| `GET /statistics/reading-stats` | Reading and summarization statistics |
| `POST /statistics/topics/cluster` | Trigger topic clustering |
| `GET /statistics/topics/trends` | Historical topic trends |
| `GET /status` | Health check |
| `GET /auth/status` | OAuth status |
| `GET /auth/login/{provider}` | OAuth login (google/github) |

## Keyboard Shortcuts

### macOS App

#### File & Feeds
| Shortcut | Action |
|----------|--------|
| `⌘N` | Add new feed |
| `⌘⇧R` | Refresh all feeds |
| `⌘⇧I` | Import OPML |
| `⌘⇧E` | Export OPML |
| `⌘,` | Settings |

#### Navigation
| Shortcut | Action |
|----------|--------|
| `⌘K` | Quick open |
| `⌘]` | Next article |
| `⌘[` | Previous article |
| `j` / `k` | Navigate articles (vim-style) |
| `n` | Next unread |

#### Filters
| Shortcut | Action |
|----------|--------|
| `⌘1` | Show All |
| `⌘2` | Show Unread |
| `⌘3` | Show Saved |
| `⌘4` | Show Today |

#### Article Actions
| Shortcut | Action |
|----------|--------|
| `⌘↩` | Open in browser |
| `⌘O` | Open original |
| `⌘⇧S` | Summarize article |
| `⌘B` | Toggle bookmark |
| `⌘L` | Copy link |
| `⌘⇧C` | Copy article URL |
| `⌘R` | Mark as read |
| `⌘U` | Mark as unread |
| `⌘⇧K` | Mark all as read |

#### View
| Shortcut | Action |
|----------|--------|
| `⌘⇧F` | Toggle reader mode |
| `⌘+` | Increase font size |
| `⌘-` | Decrease font size |
| `⌘0` | Reset font size |

#### Selection
| Shortcut | Action |
|----------|--------|
| `⌘A` | Select all articles |
| `Esc` | Clear selection |

### Web App

| Shortcut | Action |
|----------|--------|
| `j` / `k` | Navigate articles |
| `g` | Go to first article |
| `m` | Toggle read/unread |
| `s` | Toggle bookmark |
| `o` | Open in browser |
| `r` | Refresh feeds |
| `/` | Focus search |
| `Esc` | Clear search |
| `⌘,` | Open settings |
| `⌘N` | Add new feed |

## Documentation

- [DEPLOYMENT.md](DEPLOYMENT.md) - Cloud deployment to Railway + Vercel
- [DOCTRINE.md](DOCTRINE.md) - Architecture and design decisions
- [SUMMARIZATION_PROMPTS.md](SUMMARIZATION_PROMPTS.md) - AI prompt engineering
- [web/README.md](web/README.md) - Web PWA documentation

## License

MIT
