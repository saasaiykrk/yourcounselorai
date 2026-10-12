"""Which AI the eval runners use: --provider anthropic (default, the pinned Claude model) or gemini.
Keys come from the environment (GitHub secrets in CI), never from the command line."""
from __future__ import annotations

import os


def model_from_env(provider: str = "anthropic"):
    if provider == "gemini":
        from app.gemini_client import GeminiClient
        return GeminiClient(os.environ["GEMINI_API_KEY"], os.environ["GEMINI_MODEL"])
    from app.claude_client import AnthropicClient
    return AnthropicClient(os.environ["ANTHROPIC_API_KEY"], os.environ["CLAUDE_MODEL"])
