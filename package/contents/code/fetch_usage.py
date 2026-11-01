#!/usr/bin/env python3
"""Fetch Claude 5-hour / weekly usage using Claude Code's local OAuth token.

The usage endpoint is tightly rate-limited, so results are cached in
~/.cache/claude-usage/usage.json and shared by every widget instance. The API
is called at most once per MIN_INTERVAL seconds, and after a 429 we wait for
the server's Retry-After before trying again.

Prints a single JSON object to stdout, e.g.
  {"five_hour": {"utilization": 52.0, "resets_at": 1793588399.8},
   "seven_day": {"utilization": 68.0, "resets_at": 1793660399.8},
   "fetched_at": 1793580000.0}
plus "error": "..." when the latest attempt failed (the last good data, if
any, is still included). Always exits 0 so the widget can read stdout.
"""
import fcntl
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime

CRED_PATH = os.path.expanduser("~/.claude/.credentials.json")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "claude-usage")
CACHE_PATH = os.path.join(CACHE_DIR, "usage.json")
LOCK_PATH = os.path.join(CACHE_DIR, "lock")
URL = "https://api.anthropic.com/api/oauth/usage"

MIN_INTERVAL = 300      # seconds between real API calls
DEFAULT_BACKOFF = 300   # used when a 429 has no usable Retry-After
ERROR_RETRY = 60        # wait after other failures (network, 5xx)


def to_epoch(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value).timestamp()
    except ValueError:
        return None


def load_cache():
    try:
        with open(CACHE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_cache(cache):
    tmp = CACHE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f)
    os.replace(tmp, CACHE_PATH)


def fetch():
    """Returns (data, error, retry_after_seconds)."""
    try:
        with open(CRED_PATH) as f:
            oauth = json.load(f)["claudeAiOauth"]
        token = oauth["accessToken"]
    except (OSError, ValueError, KeyError):
        return None, "No Claude Code login found", ERROR_RETRY

    expires_ms = oauth.get("expiresAt")
    if expires_ms and expires_ms / 1000 < time.time():
        return None, "Login token expired - run Claude Code to refresh it", ERROR_RETRY

    req = urllib.request.Request(
        URL,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-usage-plasmoid/1.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = json.load(resp)
    except urllib.error.HTTPError as e:
        if e.code == 429:
            try:
                wait = int(e.headers.get("retry-after", ""))
            except ValueError:
                wait = DEFAULT_BACKOFF
            return None, "Rate limited by usage API - retrying shortly", max(wait, 30)
        if e.code == 401:
            return None, "Login token rejected - run Claude Code to refresh it", ERROR_RETRY
        return None, f"Usage API returned HTTP {e.code}", ERROR_RETRY
    except Exception as e:  # network down, timeout, bad JSON
        return None, f"Could not reach usage API ({e.__class__.__name__})", ERROR_RETRY

    data = {}
    for key in ("five_hour", "seven_day"):
        block = raw.get(key) or {}
        data[key] = {
            "utilization": block.get("utilization"),
            "resets_at": to_epoch(block.get("resets_at")),
        }
    return data, None, MIN_INTERVAL


def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(LOCK_PATH, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # one fetch at a time across instances
        cache = load_cache()
        now = time.time()

        if now >= cache.get("next_fetch", 0):
            data, error, wait = fetch()
            cache["next_fetch"] = now + wait
            cache["error"] = error
            if data:
                cache["data"] = data
                cache["fetched_at"] = now
            save_cache(cache)

    out = dict(cache.get("data") or {})
    if cache.get("fetched_at"):
        out["fetched_at"] = cache["fetched_at"]
    if cache.get("error"):
        out["error"] = cache["error"]
    print(json.dumps(out))


if __name__ == "__main__":
    main()
    sys.exit(0)
