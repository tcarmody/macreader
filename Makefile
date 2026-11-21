.PHONY: setup run test clean init-db rebuild app app-build app-sign app-verify app-run app-clean format typecheck

# Setup development environment. uv installs the Python in .python-version
# (3.14) itself, so the system python3 doesn't matter. Install uv once with
# `brew install uv`.
setup:
	uv sync
	mkdir -p data
	@echo "Setup complete. Copy .env.example to .env and add your API key."
	@echo "Run 'make run' to start the server."

# Run development server
run:
	uv run uvicorn backend.server:app --reload --port 5005

# Run tests
test:
	uv run pytest backend/tests/ -v

# Clean generated files
clean:
	rm -rf __pycache__ .pytest_cache
	find . -type d -name "__pycache__" -not -path "./.venv/*" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -not -path "./.venv/*" -delete 2>/dev/null || true

# Initialize database
init-db:
	uv run python -c "from backend.database import Database; from pathlib import Path; Database(Path('data/articles.db'))"
	@echo "Database initialized at data/articles.db"

# Full rebuild
rebuild: clean setup init-db
	@echo "Rebuild complete."

# macOS app (SwiftPM, no Xcode required). Built by dpcommon-macapp from the
# shared package; config is [tool.dpcommon.macapp] in pyproject.toml.
app:
	uv run dpcommon-macapp app

app-build:
	uv run dpcommon-macapp build

app-sign:
	uv run dpcommon-macapp sign

app-verify:
	uv run dpcommon-macapp verify

app-run:
	uv run dpcommon-macapp run

app-clean:
	rm -rf app/DataPointsAI/.build app/DataPointsAI/build

# Format code
format:
	uv run --with black black backend/

# Type check
typecheck:
	uv run --with mypy mypy backend/
