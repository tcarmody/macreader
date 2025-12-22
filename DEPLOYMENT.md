# Deploying DataPoints to the Cloud

This guide explains how to deploy the DataPoints RSS reader as a web application using **Railway** (backend) and **Vercel** (frontend).

## Architecture Overview

```
┌─────────────────┐         ┌─────────────────┐
│   Vercel        │  HTTPS  │   Railway       │
│   (Frontend)    │ ──────► │   (Backend)     │
│                 │         │                 │
│  React PWA      │         │  FastAPI        │
│  Static files   │         │  SQLite DB      │
└─────────────────┘         └─────────────────┘
```

- **Frontend**: React PWA hosted on Vercel's CDN
- **Backend**: Python FastAPI server on Railway with persistent storage
- **Database**: SQLite stored on Railway's persistent volume

## Prerequisites

- GitHub account (for connecting repositories)
- [Railway account](https://railway.app) (free tier available)
- [Vercel account](https://vercel.com) (free tier available)
- At least one LLM API key (Anthropic, OpenAI, or Google)

---

## Step 1: Deploy Backend to Railway

### 1.1 Create Railway Project

1. Go to [railway.app](https://railway.app) and sign in
2. Click **"New Project"** → **"Deploy from GitHub repo"**
3. Select your `macreader` repository
4. Railway will detect the Python project and use [Railpack](https://docs.railway.com/guides/build-configuration) to build it automatically

> **Note**: The `railway.json` file configures Railway to use Railpack (the current default builder). Nixpacks is deprecated but still supported for existing services.

### 1.2 Configure Environment Variables

In Railway dashboard, go to your service → **Variables** tab and add:

| Variable | Value | Required |
|----------|-------|----------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key | At least one LLM key |
| `OPENAI_API_KEY` | Your OpenAI API key | Optional |
| `GOOGLE_API_KEY` | Your Google AI API key | Optional |
| `CORS_ORIGINS` | `https://your-app.vercel.app` | Yes (after Vercel deploy) |
| `LOG_LEVEL` | `INFO` | Optional |

> **Note**: You can leave LLM keys empty if users will provide their own keys via the web UI.

### 1.3 Configure Persistent Storage

SQLite needs persistent storage to survive redeploys. See Railway's [Volumes documentation](https://docs.railway.com/guides/volumes) for the latest instructions.

**To add a volume:**

1. Open your project in Railway dashboard
2. Use the **Command Palette** (press `⌘K` or `Ctrl+K`) and search for "volume", or right-click on the project canvas
3. Select **"Create Volume"**
4. When prompted, select your service to attach the volume to
5. Set the **mount path** to `/app/data`
6. Add environment variable: `DB_PATH=/app/data/articles.db`
7. Also add: `CACHE_DIR=/app/data/cache`

> **Important**: Railway automatically provides `RAILWAY_VOLUME_MOUNT_PATH` environment variable at runtime once the volume is attached.

### 1.4 Verify Deployment

1. Railway will automatically deploy using the `Procfile`
2. Once deployed, go to your service → **Settings** → **Networking** to find your service URL (e.g., `https://macreader-production.up.railway.app`)
3. Test the API: `https://your-url.railway.app/status`

You should see:
```json
{
  "status": "ok",
  "summarization_enabled": true,
  "provider": "anthropic",
  "model": "claude-haiku-4-5"
}
```

---

## Step 2: Deploy Frontend to Vercel

### 2.1 Create Vercel Project

1. Go to [vercel.com](https://vercel.com) and sign in
2. Click **"Add New..."** → **"Project"**
3. Import your `macreader` repository
4. Configure the project:
   - **Framework Preset**: Vite
   - **Root Directory**: `web`
   - **Build Command**: `npm run build` (default)
   - **Output Directory**: `dist` (default)

### 2.2 Configure Environment Variables

In Vercel dashboard, go to **Settings** → **Environment Variables**:

| Variable | Value |
|----------|-------|
| `VITE_API_URL` | Your Railway backend URL (e.g., `https://macreader-production.up.railway.app`) |

> **Important**: Don't include a trailing slash in the URL.

### 2.3 Deploy

1. Click **"Deploy"**
2. Wait for the build to complete
3. Copy your Vercel URL (e.g., `https://your-app.vercel.app`)

### 2.4 Update Railway CORS

Go back to Railway and update the `CORS_ORIGINS` variable:

```
CORS_ORIGINS=https://your-app.vercel.app
```

If you have a custom domain, add it too (comma-separated):
```
CORS_ORIGINS=https://your-app.vercel.app,https://reader.yourdomain.com
```

---

## Step 3: Configure Custom Domain (Optional)

### Vercel Custom Domain

1. In Vercel dashboard → **Settings** → **Domains**
2. Add your domain (e.g., `reader.yourdomain.com`)
3. Update DNS records as instructed
4. Update Railway's `CORS_ORIGINS` to include the new domain

### Railway Custom Domain

1. In Railway dashboard → your service → **Settings** → **Networking** → **Public Networking**
2. Add your domain (e.g., `api.yourdomain.com`)
3. Update Vercel's `VITE_API_URL` to use the new domain

---

## Step 4: First-Time Setup

1. Open your Vercel URL in a browser
2. Click **"Open Settings"** when prompted
3. Enter your backend URL if not auto-detected
4. Add your LLM API key(s) for summarization
5. Click **"Save Changes"**

You're now ready to:
- Add RSS feeds
- Browse and read articles
- Generate AI summaries
- Use keyboard shortcuts (j/k to navigate, m to mark read, s to save)

---

## Troubleshooting

### "Failed to fetch" errors

1. Check that `VITE_API_URL` is set correctly in Vercel
2. Check that `CORS_ORIGINS` includes your Vercel domain in Railway
3. Verify the backend is running: visit `https://your-railway-url/status`

### Summarization not working

1. Verify at least one LLM API key is set (either in Railway env vars or in the web UI settings)
2. Check Railway logs for errors: Railway dashboard → your service → **Logs**

### Database reset on redeploy

1. Ensure you've added a persistent volume in Railway (see [Using Volumes](https://docs.railway.com/guides/volumes))
2. Verify `DB_PATH` points to the volume mount (e.g., `/app/data/articles.db`)
3. If you see "No such file or directory" errors, ensure the directory structure exists on the volume

### Build failures on Railway

1. Check that the project is using Railpack (set in `railway.json` or service settings)
2. Review build logs in Railway dashboard → your service → **Deployments**
3. See [Build Configuration](https://docs.railway.com/guides/build-configuration) for customization options

### Build failures on Vercel

1. Ensure the root directory is set to `web`
2. Check that Node.js version is 18+ (set in Vercel project settings)

---

## Cost Estimates

### Free Tier Usage

Both Railway and Vercel offer generous free tiers:

| Service | Free Tier |
|---------|-----------|
| Railway | $5/month credit, ~500 hours of runtime |
| Vercel | 100GB bandwidth, unlimited static deploys |

For personal use, you'll likely stay within free tiers.

### LLM API Costs

| Provider | Cost per 1M tokens (input/output) |
|----------|-----------------------------------|
| Anthropic Claude Haiku | $0.25 / $1.25 |
| OpenAI GPT-4o-mini | $0.15 / $0.60 |
| Google Gemini Flash | $0.075 / $0.30 |

A typical article summary uses ~2,000 input tokens and ~500 output tokens, costing approximately:
- **Haiku**: $0.001 per article
- **GPT-4o-mini**: $0.0006 per article
- **Gemini Flash**: $0.0003 per article

---

## Security Considerations

### API Keys

- **Server-side keys**: Set in Railway environment variables, never exposed to clients
- **User-provided keys**: Stored in browser localStorage, sent via HTTPS headers
- Keys are never logged or persisted on the server

### CORS

- Only domains listed in `CORS_ORIGINS` can access the API
- Always use HTTPS in production

### Database

- SQLite database is stored on Railway's persistent volume
- Not accessible from the internet
- Consider regular backups for important data

---

## Updating the Application

### Frontend Updates

Vercel automatically deploys when you push to the main branch.

### Backend Updates

Railway automatically deploys when you push to the main branch.

To manually trigger a redeploy:
1. Railway dashboard → your service → **Deployments**
2. Click **"Redeploy"** on the latest deployment

---

## Local Development

For local development, you don't need cloud services:

```bash
# Terminal 1: Start backend
source rss_venv/bin/activate
python -m uvicorn backend.server:app --reload --port 5005

# Terminal 2: Start frontend
cd web
npm run dev
```

The frontend dev server proxies `/api` requests to `localhost:5005` automatically.

---

## References

- [Railway Volumes Documentation](https://docs.railway.com/guides/volumes)
- [Railway Build Configuration](https://docs.railway.com/guides/build-configuration)
- [Railway Deployments](https://docs.railway.com/reference/deployments)
- [Vercel Documentation](https://vercel.com/docs)
