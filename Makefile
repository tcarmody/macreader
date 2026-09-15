.PHONY: setup run test clean init-db rebuild app app-build app-sign app-run app-clean

# Setup development environment
setup:
	python3 -m venv rss_venv
	./rss_venv/bin/pip install --upgrade pip
	./rss_venv/bin/pip install -r requirements.txt
	mkdir -p data
	@echo "Setup complete. Copy .env.example to .env and add your API key."
	@echo "Run 'make run' to start the server."

# Run development server
run:
	./rss_venv/bin/python -m uvicorn backend.server:app --reload --port 5005

# Run tests
test:
	./rss_venv/bin/python -m pytest backend/tests/ -v

# Clean generated files
clean:
	rm -rf __pycache__ .pytest_cache
	rm -rf backend/__pycache__ backend/**/__pycache__
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Initialize database
init-db:
	./rss_venv/bin/python -c "from backend.database import Database; from pathlib import Path; Database(Path('data/articles.db'))"
	@echo "Database initialized at data/articles.db"

# Full rebuild
rebuild: clean setup init-db
	@echo "Rebuild complete."

# macOS app (SwiftPM — no Xcode required, see app/DataPointsAI/Scripts/README.md)
app: app-build app-sign
	@echo "Built and signed app/DataPointsAI/build/DataPointsAI.app"

app-build:
	cd app/DataPointsAI && ./Scripts/build-app.sh

app-sign:
	cd app/DataPointsAI && ./Scripts/sign-app.sh

app-run:
	cd app/DataPointsAI && ./Scripts/run-app.sh

app-clean:
	rm -rf app/DataPointsAI/.build app/DataPointsAI/build

# Format code
format:
	./rss_venv/bin/python -m black backend/

# Type check
typecheck:
	./rss_venv/bin/python -m mypy backend/
