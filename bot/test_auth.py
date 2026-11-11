"""Behavioural checks for the bot authorization and secrets changes.

Runs against bot/bot.py directly (no Discord connection): `authorized` takes a
duck-typed interaction, so a tiny stub is enough.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

BOT = Path(__file__).resolve().parent
MODULE = BOT / "bot.py"


class User:
    def __init__(self, uid: int) -> None:
        self.id = uid


class Interaction:
    def __init__(self, uid: int, guild_id: int | None) -> None:
        self.user = User(uid)
        self.guild_id = guild_id


def load():
    spec = importlib.util.spec_from_file_location("mmacro_bot", MODULE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def check(label: str, actual, expected) -> None:
    status = "ok" if actual == expected else "FAIL"
    print(f"{status}: {label} -> {actual!r} (expected {expected!r})")
    if actual != expected:
        raise SystemExit(1)


def main() -> int:
    bot = load()

    # settings.ini currently has an empty AllowedUserIds: nobody is allowed.
    check("empty allowlist denies", bot.authorized(Interaction(42, 7)), False)

    # Non-empty allowlist: the listed id is allowed, others are not.
    bot.allowed_users = lambda: {42}
    bot.setting = lambda section, key, fallback="": {"GuildId": ""}.get(key, fallback)
    check("listed user allowed", bot.authorized(Interaction(42, 7)), True)
    check("other user denied", bot.authorized(Interaction(43, 7)), False)

    # Guild restriction: a configured guild excludes other guilds and DMs.
    bot.setting = lambda section, key, fallback="": {"GuildId": "999"}.get(key, fallback)
    check("matching guild allowed", bot.authorized(Interaction(42, 999)), True)
    check("foreign guild denied", bot.authorized(Interaction(42, 7)), False)
    check("DM denied when guild configured", bot.authorized(Interaction(42, None)), False)

    # Secrets live in secrets.ini and fall back to settings.ini during migration.
    original_secrets = bot.SECRETS_FILE
    with tempfile.TemporaryDirectory() as tmp:
        bot.SECRETS_FILE = Path(tmp) / "secrets.ini"
        bot.setting = lambda section, key, fallback="": "old-token" if key == "Token" else fallback
        check("token falls back to settings.ini", bot.secret("Token"), "old-token")

        bot.SECRETS_FILE.write_text("[DiscordBot]\nToken=new-token\n", encoding="utf-8-sig")
        check("token read from secrets.ini", bot.secret("Token"), "new-token")
    bot.SECRETS_FILE = original_secrets

    print("all bot checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
