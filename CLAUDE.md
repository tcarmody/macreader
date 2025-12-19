# Claude Code Project Instructions

## Python Environment

Always activate the virtual environment before running Python commands:

```bash
source rss_venv/bin/activate && <command>
```

Examples:
- Run tests: `source rss_venv/bin/activate && pytest backend/tests/ -v`
- Run server: `source rss_venv/bin/activate && python -m backend.server`
- Install deps: `source rss_venv/bin/activate && pip install -r requirements.txt`

## Project Structure

- **backend/**: Python FastAPI server
- **app/**: macOS SwiftUI application (Xcode project in `app/DataPointsAI/`)
- **data/**: SQLite database storage

## Building

- Swift app: `cd app/DataPointsAI && xcodebuild -scheme DataPointsAI build`
- Run backend tests: `source rss_venv/bin/activate && pytest backend/tests/ -v`
