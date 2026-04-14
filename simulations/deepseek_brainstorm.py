#!/usr/bin/env python3
"""
FLUX TUI Debugger — DeepSeek Brainstorm Session
=================================================

Uses deepseek-reasoner to brainstorm 10 creative improvements to flux-tui,
then uses deepseek-chat to flesh out implementation details for each idea.
Each idea is rated by **Impact** (1–10) and **Effort** (1–10).

Usage
-----
    python3 deepseek_brainstorm.py

Output
------
    simulations/brainstorm_output.md
"""

from __future__ import annotations

import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
API_BASE = "https://api.deepseek.com"
API_KEY = "sk-b20cb2eb01464f51a85d444ae91c4dec"

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_FILE = SCRIPT_DIR / "brainstorm_output.md"

MAX_RETRIES = 3
RETRY_BACKOFF = 2  # seconds

# ---------------------------------------------------------------------------
# Fleet context
# ---------------------------------------------------------------------------
FLEET_CONTEXT = """
## Fleet Context
- **SuperInstance**: Central orchestration layer managing the fleet.
- **912+ repositories**: The fleet spans over nine hundred git repositories.
- **9 agents**: Nine autonomous agents operate across the fleet.
- **FLUX ISA**: Custom instruction-set architecture with 4 runtime implementations.
- **flux-tui**: A terminal-user-interface debugger for the FLUX VM, being
  positioned as the fleet's canonical debugging tool.
- **ISA v1**: Stack-based, 52 opcodes.
- **ISA v2** (planned): Register-based evolution.
- **ISA v3** (planned): Escape-prefix opcode space + compression extensions.
- **Conformance vectors**: Currently 20; target is 161.
"""


# ---------------------------------------------------------------------------
# System prompts
# ---------------------------------------------------------------------------
REASONER_SYSTEM = (
    "You are a brilliant, creative product architect who thinks in bold, "
    "innovative directions.  You are brainstorming improvements to **flux-tui**, "
    "a terminal-based debugger for the FLUX VM (a custom ISA used across a "
    "fleet of 912+ repos and 9 agents).  Your ideas should be creative yet "
    "grounded, ambitious yet feasible.  Think beyond conventional debugger "
    "features — consider AI-assisted debugging, visualisation, collaboration, "
    "fleet-scale observability, and novel interaction paradigms."
)

ENGINEER_SYSTEM = (
    "You are a pragmatic, detail-oriented senior engineer who turns creative "
    "ideas into concrete implementation plans.  You work on **flux-tui**, a "
    "Rust-based terminal debugger for the FLUX VM.  You think about APIs, "
    "data structures, dependencies, and incremental delivery.  You always "
    "propose a realistic first iteration that could ship in 1–2 sprints."
)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class BrainstormIdea:
    """A single brainstormed improvement."""
    number: int
    title: str
    description: str  # from reasoner
    implementation: str  # from engineer
    impact: int  # 1–10
    effort: int  # 1–10
    reasoning_tokens: int = 0
    engineer_tokens: int = 0
    reasoning_latency: float = 0.0
    engineer_latency: float = 0.0


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def _headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
    }


def call_deepseek(
    model: str,
    system_prompt: str,
    user_prompt: str,
    *,
    max_tokens: int = 1024,
    temperature: float = 0.8,
) -> dict[str, Any]:
    """Call DeepSeek chat/completions with retry logic."""
    payload: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            start = time.monotonic()
            resp = httpx.post(
                f"{API_BASE}/chat/completions",
                headers=_headers(),
                json=payload,
                timeout=180.0,
            )
            latency = time.monotonic() - start

            if resp.status_code == 429:
                wait = RETRY_BACKOFF * attempt
                print(f"    ⏳  Rate-limited; waiting {wait}s …")
                time.sleep(wait)
                continue

            resp.raise_for_status()
            body = resp.json()
            body["_latency_s"] = latency
            return body

        except httpx.HTTPStatusError as exc:
            print(f"    ⚠️  HTTP {exc.response.status_code} (attempt {attempt})")
            if attempt == MAX_RETRIES:
                raise
            time.sleep(RETRY_BACKOFF * attempt)

        except httpx.RequestError as exc:
            print(f"    ⚠️  Network error: {exc} (attempt {attempt})")
            if attempt == MAX_RETRIES:
                raise
            time.sleep(RETRY_BACKOFF * attempt)

    raise RuntimeError("Unreachable")  # pragma: no cover


def extract_text(body: dict[str, Any]) -> str:
    return body["choices"][0]["message"]["content"].strip()


def extract_usage(body: dict[str, Any]) -> dict[str, int]:
    u = body.get("usage", {})
    return {
        "prompt_tokens": u.get("prompt_tokens", 0),
        "completion_tokens": u.get("completion_tokens", 0),
        "total_tokens": u.get("total_tokens", 0),
        "reasoning_tokens": u.get("reasoning_tokens", 0),
    }


# ---------------------------------------------------------------------------
# Brainstorming pipeline
# ---------------------------------------------------------------------------

def generate_ideas() -> list[dict[str, str]]:
    """Use deepseek-reasoner to brainstorm 10 ideas.  Returns parsed list."""
    prompt = (
        f"{FLEET_CONTEXT}\n\n"
        f"## Your Task\n"
        f"Brainstorm exactly **10 creative, high-impact improvements** to flux-tui.  "
        f"For each idea provide:\n"
        f"1. A short, catchy **title** (≤ 8 words)\n"
        f"2. A **description** (2–3 sentences explaining the concept)\n"
        f"3. An **impact rating** (1–10, how transformative this would be)\n"
        f"4. An **effort rating** (1–10, how much work to implement)\n\n"
        f"Format each idea EXACTLY like this (use the exact markers):\n"
        f"```\n"
        f"IDEA 1: [title]\n"
        f"DESC: [description]\n"
        f"IMPACT: [number]\n"
        f"EFFORT: [number]\n"
        f"```\n\n"
        f"Think boldly.  Some ideas should be incremental improvements and some "
        f"should be moonshots.  Cover a mix of UX, architecture, testing, fleet "
        f"integration, AI assistance, and developer experience."
    )
    print("\n🧠  Generating 10 brainstorm ideas with deepseek-reasoner …", flush=True)
    body = call_deepseek("deepseek-reasoner", REASONER_SYSTEM + FLEET_CONTEXT, prompt, max_tokens=2048)
    text = extract_text(body)
    usage = extract_usage(body)
    print(f"   Done ({body.get('_latency_s', 0):.1f}s, {usage['total_tokens']} tokens)")

    # Parse structured ideas
    ideas = []
    pattern = r"IDEA\s+(\d+):\s*(.+?)\nDESC:\s*(.+?)\nIMPACT:\s*(\d+)\nEFFORT:\s*(\d+)"
    matches = re.findall(pattern, text, re.DOTALL)
    for m in matches:
        ideas.append({
            "number": int(m[0]),
            "title": m[1].strip(),
            "description": m[2].strip(),
            "impact": int(m[3]),
            "effort": int(m[4]),
        })

    if len(ideas) < 10:
        print(f"   ⚠️  Only parsed {len(ideas)}/10 ideas from response; filling gaps …")
        # Try a looser parse
        blocks = re.split(r"IDEA\s+\d+:", text)
        for i, block in enumerate(blocks[1:], 1):
            if i > len(ideas):
                desc_match = re.search(r"DESC:\s*(.+?)(?:\nIMPACT:|$)", block, re.DOTALL)
                imp_match = re.search(r"IMPACT:\s*(\d+)", block)
                eff_match = re.search(r"EFFORT:\s*(\d+)", block)
                if desc_match:
                    ideas.append({
                        "number": i,
                        "title": block.strip().split("\n")[0].strip()[:60],
                        "description": desc_match.group(1).strip()[:300],
                        "impact": int(imp_match.group(1)) if imp_match else 7,
                        "effort": int(eff_match.group(1)) if eff_match else 5,
                    })

    return ideas[:10]


def flesh_out_implementation(idea: dict[str, Any], index: int) -> tuple[str, dict[str, int], float]:
    """Use deepseek-chat to provide implementation details for one idea."""
    prompt = (
        f"{FLEET_CONTEXT}\n\n"
        f"## Your Task\n"
        f"You are fleshing out implementation details for a flux-tui improvement idea.\n\n"
        f"**Idea #{idea['number']}: {idea['title']}**\n"
        f"{idea['description']}\n\n"
        f"Please provide a **concrete implementation plan** (3–5 paragraphs) that covers:\n"
        f"1. **Architecture**: What components change? New modules? Modified data structures?\n"
        f"2. **Dependencies**: Any new Rust crates, external tools, or API integrations?\n"
        f"3. **First iteration**: What's the minimum viable version that could ship in 1 sprint?\n"
        f"4. **Testing approach**: How would we verify this works correctly?\n"
        f"5. **Risks**: What could go wrong? What are the unknowns?\n\n"
        f"Be specific — name actual crate names, file paths, data structures where possible."
    )
    body = call_deepseek("deepseek-chat", ENGINEER_SYSTEM + FLEET_CONTEXT, prompt, max_tokens=1024)
    text = extract_text(body)
    usage = extract_usage(body)
    latency = body.get("_latency_s", 0)
    return text, usage, latency


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------

def build_markdown(
    ideas: list[BrainstormIdea],
    total_tokens: int,
    total_time: float,
) -> str:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines: list[str] = []
    w = lines.append

    w("# 💡 FLUX TUI Brainstorm — 10 Creative Improvements")
    w("")
    w(f"**Date:** {ts}")
    w(f"**Models:** deepseek-reasoner (ideation) + deepseek-chat (implementation)")
    w(f"**Total tokens:** {total_tokens:,}")
    w(f"**Total time:** {total_time:.1f}s")
    w("")
    w("---")
    w("")

    # Summary table
    w("## Summary Table")
    w("")
    w("| # | Idea | Impact | Effort | Priority |")
    w("|---|------|--------|--------|----------|")
    for idea in ideas:
        priority = idea.impact / idea.effort
        priority_label = "🔥" if priority >= 1.5 else "⭐" if priority >= 1.0 else "📌"
        w(f"| {idea.number} | {idea.title} | {idea.impact}/10 | {idea.effort}/10 | {priority_label} {priority:.1f} |")
    w("")
    w("---")
    w("")

    # Detailed cards
    for idea in ideas:
        w(f"## Idea {idea.number}: {idea.title}")
        w("")
        w(f"**Impact:** {'🔴' * (idea.impact // 2)}{'🟡' * (1 if idea.impact % 2 else 0)} {idea.impact}/10  ")
        w(f"**Effort:** {'🔴' * (idea.effort // 2)}{'🟡' * (1 if idea.effort % 2 else 0)} {idea.effort}/10")
        w("")
        w("### 🧠 Vision (deepseek-reasoner)")
        w("")
        w(idea.description)
        w("")
        w("### 🔧 Implementation Plan (deepseek-chat)")
        w("")
        w(idea.implementation)
        w("")
        w("---")
        w("")

    # Prioritisation matrix
    w("## 📊 Prioritisation Matrix")
    w("")
    w("Ideas ranked by **Impact / Effort** ratio (bang-for-buck):")
    w("")
    sorted_ideas = sorted(ideas, key=lambda i: i.impact / i.effort, reverse=True)
    w("| Rank | Idea | Impact | Effort | I/E Ratio | Recommendation |")
    w("|------|------|--------|--------|-----------|----------------|")
    for rank, idea in enumerate(sorted_ideas, 1):
        ratio = idea.impact / idea.effort
        if ratio >= 1.5:
            rec = "✅ Do first"
        elif ratio >= 1.0:
            rec = "🔄 Schedule"
        else:
            rec = "⏳ Backlog"
        w(f"| {rank} | {idea.title} | {idea.impact} | {idea.effort} | {ratio:.2f} | {rec} |")
    w("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print("=" * 64)
    print("  FLUX TUI BRAINSTORM SESSION")
    print(f"  Output → {OUTPUT_FILE}")
    print("=" * 64)

    start_total = time.monotonic()
    total_tokens = 0

    # Phase 1: Generate ideas
    raw_ideas = generate_ideas()
    print(f"\n✅  Generated {len(raw_ideas)} ideas")

    # Phase 2: Flesh out each idea IN PARALLEL
    print(f"\n  Fleshing out {len(raw_ideas)} ideas in parallel …", flush=True)
    final_ideas: list[BrainstormIdea] = [None] * len(raw_ideas)  # type: ignore[list-item]

    def _fill_idea(idx, idea):
        try:
            impl_text, usage, latency = flesh_out_implementation(idea, idx)
            return (idx, idea, impl_text, usage, latency, None)
        except Exception as exc:
            return (idx, idea, f"*Implementation failed: {exc}*", {"total_tokens": 0}, 0.0, exc)

    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = {pool.submit(_fill_idea, i, idea): i for i, idea in enumerate(raw_ideas)}
        for future in as_completed(futures):
            idx, idea, impl_text, usage, latency, exc = future.result()
            total_tokens += usage["total_tokens"]
            status = "OK" if exc is None else "FAILED"
            print(f"    [{idx+1}/{len(raw_ideas)}] {idea['title'][:40]}  {status} ({latency:.1f}s)")
            final_ideas[idx] = BrainstormIdea(
                number=idea["number"],
                title=idea["title"],
                description=idea["description"],
                implementation=impl_text,
                impact=idea["impact"],
                effort=idea["effort"],
                reasoning_latency=0,
                engineer_latency=latency,
                engineer_tokens=usage["total_tokens"],
            )

    total_time = time.monotonic() - start_total

    # Render and save
    markdown = build_markdown(final_ideas, total_tokens, total_time)
    OUTPUT_FILE.write_text(markdown, encoding="utf-8")

    print(f"\n✅  Done!  Output saved to {OUTPUT_FILE}")
    print(f"   Total tokens: {total_tokens:,}")
    print(f"   Total time:   {total_time:.1f}s")
    print(f"   Ideas:        {len(final_ideas)}")


if __name__ == "__main__":
    main()
