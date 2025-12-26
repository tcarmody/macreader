"""
Gmail Polling Scheduler.

Background task that periodically fetches newsletters from Gmail.
"""

import asyncio
import logging
from datetime import datetime
from typing import TYPE_CHECKING

from .imap import fetch_newsletters_from_gmail

if TYPE_CHECKING:
    from ..database import Database


logger = logging.getLogger(__name__)


class GmailPollingScheduler:
    """
    Background scheduler for Gmail newsletter polling.

    Periodically checks Gmail for new newsletters and imports them.
    """

    def __init__(self, db: "Database"):
        self.db = db
        self._task: asyncio.Task | None = None
        self._running = False
        self._interval_minutes = 30

    async def start(self):
        """Start the polling scheduler."""
        config = self.db.get_gmail_config()

        if not config:
            logger.info("Gmail not configured, scheduler not started")
            return

        if not config.get("is_enabled", True):
            logger.info("Gmail polling disabled, scheduler not started")
            return

        self._interval_minutes = config.get("poll_interval_minutes", 30)
        self._running = True
        self._task = asyncio.create_task(self._poll_loop())
        logger.info(f"Gmail polling scheduler started (interval: {self._interval_minutes} minutes)")

    async def stop(self):
        """Stop the polling scheduler."""
        self._running = False

        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

        logger.info("Gmail polling scheduler stopped")

    async def restart(self):
        """Restart the scheduler with updated configuration."""
        await self.stop()
        await self.start()

    async def poll_now(self):
        """Trigger an immediate poll."""
        if not self._running:
            logger.warning("Scheduler not running, cannot poll")
            return

        logger.info("Triggering immediate Gmail poll")
        await self._do_poll()

    async def _poll_loop(self):
        """Main polling loop."""
        # Initial delay to let the server fully start
        await asyncio.sleep(10)

        while self._running:
            try:
                # Refresh configuration
                config = self.db.get_gmail_config()

                if not config:
                    logger.info("Gmail configuration removed, stopping scheduler")
                    self._running = False
                    break

                if not config.get("is_enabled", True):
                    logger.info("Gmail polling disabled, stopping scheduler")
                    self._running = False
                    break

                # Update interval if changed
                new_interval = config.get("poll_interval_minutes", 30)
                if new_interval != self._interval_minutes:
                    self._interval_minutes = new_interval
                    logger.info(f"Polling interval updated to {self._interval_minutes} minutes")

                # Perform the poll
                await self._do_poll()

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.exception(f"Error in Gmail polling loop: {e}")

            # Wait for next poll
            await asyncio.sleep(self._interval_minutes * 60)

    async def _do_poll(self):
        """Perform a single poll operation."""
        try:
            logger.info(f"Polling Gmail at {datetime.now().isoformat()}")
            result = await fetch_newsletters_from_gmail(self.db)

            if result.success:
                if result.imported > 0:
                    logger.info(f"Gmail poll: imported {result.imported} newsletters")
                else:
                    logger.debug("Gmail poll: no new newsletters")
            else:
                logger.warning(f"Gmail poll failed: {result.message}")

        except Exception as e:
            logger.exception(f"Gmail poll error: {e}")


# Global scheduler instance (initialized by server.py)
gmail_scheduler: GmailPollingScheduler | None = None


async def start_gmail_scheduler(db: "Database"):
    """Start the global Gmail scheduler."""
    global gmail_scheduler
    gmail_scheduler = GmailPollingScheduler(db)
    await gmail_scheduler.start()


async def stop_gmail_scheduler():
    """Stop the global Gmail scheduler."""
    global gmail_scheduler
    if gmail_scheduler:
        await gmail_scheduler.stop()
        gmail_scheduler = None
