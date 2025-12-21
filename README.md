# Data Points AI

A modern macOS RSS reader with AI-powered summarization and intelligent article clustering.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Python](https://img.shields.io/badge/Python-3.11%2B-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

## Features

- **RSS Feed Management** - Subscribe to feeds, organize by category, import/export OPML
- **AI Summarization** - Automatic article summaries with key points extraction
- **Multi-Provider LLM Support** - Choose between Anthropic Claude, OpenAI GPT, or Google Gemini
- **Topic Clustering** - Group articles by semantic topics using AI analysis
- **Full-Text Search** - Fast search across all articles with SQLite FTS5
- **Native macOS Experience** - SwiftUI interface with Keychain, Spotlight, and notification integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS SwiftUI App                         │
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

## Getting Started

### Prerequisites

- macOS 13.0+
- Python 3.11+
- Xcode 15+ (for building the Swift app)
- An API key from at least one LLM provider:
  - [Anthropic](https://console.anthropic.com/) (recommended - supports prompt caching for 90% cost reduction)
  - [OpenAI](https://platform.openai.com/)
  - [Google AI](https://aistudio.google.com/)

### Backend Setup

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
echo "ANTHROPIC_API_KEY=your-key-here" > .env

# Initialize the database
make init-db

# Start the server
make run
```

The backend server runs on `http://localhost:5005`.

### macOS App

```bash
# Build the app
cd app/DataPointsAI
xcodebuild -scheme DataPointsAI build

# Or open in Xcode
open DataPointsAI.xcodeproj
```

On first launch, the app will guide you through API key configuration via a setup wizard.

## Configuration

Create a `.env` file in the project root:

```bash
# LLM Provider (required - choose at least one)
ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
# GOOGLE_API_KEY=AI...

# Provider selection (default: anthropic)
LLM_PROVIDER=anthropic

# Server settings
PORT=5005
LOG_LEVEL=INFO

# Advanced features (optional)
ENABLE_JS_RENDER=false      # JavaScript rendering for dynamic content
ENABLE_ARCHIVE=false        # Archive service for paywalled content
```

## Development

```bash
# Run tests
source rss_venv/bin/activate && pytest backend/tests/ -v

# Format code
make format

# Type checking
make typecheck

# Full rebuild
make rebuild
```

## Project Structure

```
macreader/
├── app/                    # macOS SwiftUI application
│   └── DataPointsAI/
│       └── DataPointsAI/
│           ├── App/        # Entry point
│           ├── Models/     # Data models
│           ├── Views/      # UI components
│           └── Services/   # Network, storage, system services
├── backend/                # Python FastAPI server
│   ├── routes/             # API endpoints
│   ├── providers/          # LLM provider integrations
│   ├── advanced/           # JS rendering, archive fallbacks
│   ├── database.py         # SQLite operations
│   ├── summarizer.py       # AI summarization
│   ├── clustering.py       # Topic clustering
│   └── tests/              # Test suite
├── data/                   # SQLite database
├── requirements.txt        # Python dependencies
└── Makefile               # Build commands
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /articles` | List articles with filtering |
| `GET /articles/grouped` | Get articles grouped by date/feed/topic |
| `POST /articles/{id}/summarize` | Trigger AI summarization |
| `GET /feeds` | List subscribed feeds |
| `POST /feeds` | Subscribe to a new feed |
| `POST /feeds/refresh` | Refresh all feeds |
| `POST /feeds/import-opml` | Import OPML file |
| `GET /feeds/export-opml` | Export feeds as OPML |
| `GET /health` | Server health check |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘N` | Add new feed |
| `⌘R` | Refresh feeds |
| `⌘⇧I` | Import OPML |
| `⌘⇧E` | Export OPML |
| `⌘,` | Settings |

## License

MIT
