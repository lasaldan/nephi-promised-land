#!/usr/bin/env python3
"""Generates voice clips with LuvVoice for every manifest row that is missing
or stale, saving them to voice/<character>/<clip>.mp3.

The API token is read from the LUVVOICE_API_TOKEN environment variable.

    python3 tools/voice/generate.py --dry-run          # what would be made, and how many characters
    python3 tools/voice/generate.py --character lehi --limit 3   # try a few first
    python3 tools/voice/generate.py                    # everything missing or stale
    python3 tools/voice/generate.py --clip I_WILL_FATHER_FA2959 --force
    python3 tools/voice/generate.py --character narrator   # the scripture scroll verses
    python3 tools/voice/generate.py --list-voices cloned
    python3 tools/voice/generate.py --locale es --dry-run   # Spanish: cast_es.json, voice/es/

Run build_manifest.py first so the manifest matches the dialogue. The manifest
is saved after every clip, so a stopped run picks up where it left off.
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

from voice_common import (CAST_FILE, MANIFEST_FILE, add_locale_argument, clip_path, load_cast, read_manifest,
                          refresh_status, text_to_send, write_manifest)

API_URL = "https://luvvoice.com/api/v1/text-to-speech"
# Cloudflare in front of LuvVoice blocks urllib's default User-Agent with
# "error code: 1010" (a 403).
USER_AGENT = "nephi-voice-tools/1.0"

# LuvVoice allows 10 requests a minute (plus 5 a second and 20 per 10 seconds,
# which 10 a minute never reaches). One request every 6.5 seconds stays under it
# with room for clock drift.
MIN_GAP_SECONDS = 6.5
# 429s and 500s are retried with exponential backoff: 10s, 20s, 40s, 80s, 160s.
MAX_RETRIES = 5
BACKOFF_START_SECONDS = 10
# Free accounts can send 3,000 characters a request, paid ones 20,000.
MAX_CHARACTERS = 3000

# Statuses that retrying won't fix. The manifest is saved after each clip, so
# rerunning once the cause is fixed carries on from here.
FATAL = {
    401: "The API token is invalid or missing. Check LUVVOICE_API_TOKEN.",
    402: "Out of credits. Buy more on luvvoice.com, then run this again to carry on.",
    403: "API access was denied. The API needs the Plus plan or higher "
         "(\"error code: 1010\" instead means Cloudflare blocked the request's User-Agent).",
}


class SkipClip(Exception):
    """This clip can't be made as sent (a 400), but the rest of the run can go on."""


class Throttle:
    """Spaces requests MIN_GAP_SECONDS apart, and waits out the window when the
    rate-limit headers say none are left."""

    def __init__(self):
        self.next_allowed = 0.0

    def wait(self):
        delay = self.next_allowed - time.monotonic()
        if delay > 0:
            time.sleep(delay)

    def update(self, headers, retry_after=None):
        gap = MIN_GAP_SECONDS if retry_after is None else retry_after
        remaining = _int_header(headers, "X-RateLimit-Remaining")
        reset = _int_header(headers, "X-RateLimit-Reset")
        if remaining == 0 and reset is not None:
            print(f"      rate limit reached; waiting {reset}s for it to reset")
            gap = max(gap, reset + 1)
        self.next_allowed = time.monotonic() + gap


def _int_header(headers, name):
    try:
        return int(headers.get(name)) if headers and headers.get(name) is not None else None
    except ValueError:
        return None


def _error_message(body):
    try:
        data = json.loads(body)
        return data.get("error") or data.get("message") or body
    except ValueError:
        return body


def request(method, url, token, throttle, body=None):
    """Sends one API request, retrying 429s, 500s and network errors with
    backoff. Exits on 401, 402 and 403; raises SkipClip on 400."""
    data = json.dumps(body).encode("utf-8") if body is not None else None
    backoff = BACKOFF_START_SECONDS
    for attempt in range(MAX_RETRIES + 1):
        throttle.wait()
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        })
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                throttle.update(response.headers)
                return json.load(response)
        except urllib.error.HTTPError as e:
            message = _error_message(e.read().decode("utf-8", "replace"))
            if e.code in FATAL:
                sys.exit(f"HTTP {e.code}: {FATAL[e.code]}\n  LuvVoice said: {message}")
            if e.code == 400:
                throttle.update(e.headers)
                raise SkipClip(message)
            if e.code not in (429, 500, 502, 503, 504):
                sys.exit(f"LuvVoice returned HTTP {e.code}: {message}")
            # On a 429, the reset header says how long the window has left.
            wait = backoff
            if e.code == 429:
                wait = max(wait, (_int_header(e.headers, "X-RateLimit-Reset") or 0) + 1)
            problem = f"HTTP {e.code} ({message})"
            throttle.update(e.headers, retry_after=wait)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            wait = backoff
            problem = f"network error ({getattr(e, 'reason', e)})"
            throttle.update(None, retry_after=wait)
        if attempt == MAX_RETRIES:
            sys.exit(f"Giving up after {MAX_RETRIES} retries: {problem}. Run again later to carry on.")
        print(f"      {problem}; retrying in {wait}s")
        backoff *= 2


def list_voices(token, voice_type):
    url = f"{API_URL}?action=voices"
    if voice_type:
        url += f"&type={voice_type}"
    print(json.dumps(request("GET", url, token, Throttle()), indent=2))


def synthesize(token, throttle, text, character_cast):
    body = {
        "text": text,
        "voice_id": character_cast["voice_id"],
        "rate": character_cast.get("rate", 0),
        "pitch": character_cast.get("pitch", 0),
        "volume": character_cast.get("volume", 0),
    }
    if character_cast.get("voice_type") == "cloned":
        body["voice_type"] = "cloned"
    result = request("POST", API_URL, token, throttle, body)
    if not result.get("success"):
        raise SkipClip(f"no audio in the response: {json.dumps(result)[:300]}")
    # Standard voices send the mp3 inline; cloned ones send a link to it.
    if result.get("audio_data"):
        return result, base64.b64decode(result["audio_data"], validate=True)
    if result.get("audio_url"):
        return result, download(result["audio_url"])
    raise SkipClip(f"no audio in the response: {json.dumps(result)[:300]}")


def download(url):
    """Fetches a cloned voice's mp3, retrying network errors and 5xxs. The
    credits are already spent, so a failure stops the run rather than skipping."""
    backoff = BACKOFF_START_SECONDS
    for attempt in range(MAX_RETRIES + 1):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code < 500:
                sys.exit(f"Downloading {url} failed with HTTP {e.code}. The credits were spent; "
                         "fetch it by hand if the link still works.")
            problem = f"HTTP {e.code}"
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            problem = f"network error ({getattr(e, 'reason', e)})"
        if attempt == MAX_RETRIES:
            sys.exit(f"Giving up downloading {url} after {MAX_RETRIES} retries: {problem}. "
                     "The credits were spent; fetch it by hand if the link still works.")
        print(f"      download {problem}; retrying in {backoff}s")
        time.sleep(backoff)
        backoff *= 2


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_locale_argument(parser)
    parser.add_argument("--character", action="append", help="only this speaker (repeatable)")
    parser.add_argument("--clip", action="append", help="only this clip (repeatable)")
    parser.add_argument("--limit", type=int, help="stop after this many clips")
    parser.add_argument("--force", action="store_true", help="regenerate even clips that are done")
    parser.add_argument("--dry-run", action="store_true", help="list what would be generated, call nothing")
    parser.add_argument("--list-voices", nargs="?", const="", metavar="TYPE",
                        help="print the voices the API lists (TYPE: cloned or standard) and exit")
    args = parser.parse_args()

    token = os.environ.get("LUVVOICE_API_TOKEN", "")
    if not token and not args.dry_run:
        sys.exit("Set LUVVOICE_API_TOKEN to your LuvVoice API token first.")
    if args.list_voices is not None:
        list_voices(token, args.list_voices)
        return

    cast = load_cast()
    rows = read_manifest()
    if not rows:
        sys.exit(f"{MANIFEST_FILE} is empty or missing; run build_manifest.py first.")
    for row in rows:
        refresh_status(row, cast)

    wanted = {"missing", "stale"} | ({"done"} if args.force else set())
    todo = [r for r in rows
            if r["status"] in wanted
            and (not args.character or r["character"] in args.character)
            and (not args.clip or r["clip"] in args.clip)]
    if args.limit:
        todo = todo[:args.limit]

    unvoiced = sorted({r["character"] for r in rows if r["status"] == "no voice"})
    if unvoiced:
        print(f"No voice_id in {CAST_FILE.name} yet, so skipped: {', '.join(unvoiced)}")
    too_long = [r for r in todo if len(text_to_send(r)) > MAX_CHARACTERS]
    for r in too_long:
        print(f"  warning: {r['character']}/{r['clip']} is over {MAX_CHARACTERS} characters, "
              "the limit on free accounts; split the line if it fails")
    total_chars = sum(len(text_to_send(r)) for r in todo)
    minutes = len(todo) * MIN_GAP_SECONDS / 60
    print(f"{len(todo)} clips to generate, {total_chars} characters, about {minutes:.0f} minutes at 10 a minute")

    if args.dry_run:
        for r in todo:
            print(f"  [{r['status']}] {r['character']}/{r['clip']}: {text_to_send(r)}")
        return

    throttle = Throttle()
    credits_used, made, skipped = 0, 0, []
    try:
        for n, row in enumerate(todo, 1):
            character_cast = cast["characters"][row["character"]]
            text = text_to_send(row)
            print(f"  {n}/{len(todo)} {row['character']}/{row['clip']}: {text}")
            try:
                result, audio = synthesize(token, throttle, text, character_cast)
            except (SkipClip, ValueError) as e:
                print(f"      skipped: {e}")
                skipped.append(f"{row['character']}/{row['clip']}: {e}")
                continue

            # Written to a temporary name first, so a run stopped mid-write
            # never leaves a broken mp3 that looks finished.
            path = clip_path(row["character"], row["clip"])
            path.parent.mkdir(parents=True, exist_ok=True)
            partial = path.with_suffix(".mp3.part")
            partial.write_bytes(audio)
            partial.replace(path)

            row["generated_hash"] = row["hash"]
            refresh_status(row, cast)
            write_manifest(rows)
            made += 1
            credits_used += result.get("credits_consumed") or 0
            print(f"      {(result.get('duration_ms') or 0) / 1000:.1f}s, "
                  f"{result.get('credits_consumed')} credits, {result.get('credits_remaining')} left")
    except KeyboardInterrupt:
        print("\nStopped. Clips made so far are saved; run again to carry on.")

    print(f"Made {made} clips with {credits_used} credits.")
    if skipped:
        print(f"{len(skipped)} skipped (LuvVoice rejected the text; try a tts_override in the manifest):")
        for s in skipped:
            print(f"  {s}")
    if made:
        print("Listen to the new clips, then switch to the Godot editor so it imports them.")


if __name__ == "__main__":
    main()
