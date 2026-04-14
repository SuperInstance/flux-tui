#!/usr/bin/env python3
"""
FLUX TUI Debugger — Roundtable Simulation
==========================================

A multi-role roundtable discussion about improving the FLUX TUI debugger,
powered by the DeepSeek API. Five expert roles discuss five critical topics
relevant to the FLUX ISA ecosystem (SuperInstance, 912+ repos, 9 agents).

Strategy: One batched API call per topic (all 5 roles in one prompt) using
deepseek-chat, plus a final synthesis call using deepseek-reasoner.
Total API calls: 6 (5 topics + 1 synthesis).

Roles
-----
- Architect         : High-level TUI design & architecture
- VM Engineer       : Opcode semantics, memory model, ISA
- QA Lead           : Testing strategy, conformance, edge cases
- Fleet Coordinator : Cross-runtime compat, fleet integration
- DevOps            : CI/CD, build optimisation, deployment

Usage
-----
    python3 roundtable.py

Output
------
    simulations/roundtable_output.md
"""

from __future__ import annotations

import json
import os
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
OUTPUT_FILE = SCRIPT_DIR / "roundtable_output.md"

MAX_RETRIES = 3
RETRY_BACKOFF = 5  # seconds

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class TokenUsage:
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    reasoning_tokens: int = 0

    def merge(self, other: dict[str, int]) -> None:
        self.prompt_tokens += other.get("prompt_tokens", 0)
        self.completion_tokens += other.get("completion_tokens", 0)
        self.total_tokens += other.get("total_tokens", 0)
        self.reasoning_tokens += other.get("reasoning_tokens", 0)


@dataclass
class CallRecord:
    label: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    reasoning_tokens: int
    latency_s: float


@dataclass
class RoleResponse:
    role: str
    model: str
    text: str


# ---------------------------------------------------------------------------
# Fleet context
# ---------------------------------------------------------------------------
FLEET_CONTEXT = """## Fleet Context
You are part of the FLUX ecosystem:
- **SuperInstance**: Central orchestration layer managing the fleet.
- **912+ repositories**: The fleet spans over nine hundred git repositories.
- **9 agents**: Nine autonomous agents operate across the fleet.
- **FLUX ISA**: Custom instruction-set architecture with 4 runtime implementations
  (currently incompatible opcode numbering).
- **flux-tui**: A terminal-user-interface debugger for the FLUX VM, being
  positioned as the fleet's canonical debugging tool.
- **ISA v1**: Stack-based, 52 opcodes.
- **ISA v2** (planned): Register-based evolution.
- **ISA v3** (planned): Escape-prefix opcode space + compression extensions.
- **Conformance vectors**: Currently 20 test vectors; target is 161."""

ROLE_PROFILES = """
The five participants are:
1. **Architect** (deepseek-reasoner persona) — Senior systems-design thinker
   with 20 years building developer tools, debuggers, and TUI applications.
   References gdb, lldb, rr, lazygit, massif. Favors clean abstractions.
2. **VM Engineer** (deepseek-chat persona) — Low-level systems programmer
   expert in opcode tables, memory models, JVM/BEAM/Wasm/custom ISAs.
   Cares about encoding efficiency, correctness, faithful VM state display.
3. **QA Lead** (deepseek-chat persona) — Testing strategist: conformance
   suites, fuzz harnesses, property-based tests, CI quality gates.
   Data-driven: metrics on conformance, regression rates, flake ratios.
4. **Fleet Coordinator** (deepseek-reasoner persona) — Distributed-system
   coordination expert. How one debugger serves 9 agents across 912+ repos
   without version-skew. Protocol versioning, graceful degradation.
5. **DevOps** (deepseek-chat persona) — CI/CD pipeline architect.
   Reproducible builds, multi-platform binaries, fast CI, caching, zero-downtime."""

# ---------------------------------------------------------------------------
# Topics
# ---------------------------------------------------------------------------
TOPICS = [
    {
        "id": "a",
        "title": "Cross-Runtime ISA Convergence",
        "question": (
            "Currently the FLUX ecosystem has **4 runtime implementations** with "
            "**incompatible opcode numbering**.  How should we converge on a single "
            "canonical opcode table?  What migration strategy minimises breakage "
            "across the fleet's 912+ repositories?  Should we use a translation "
            "layer, a unified opcode registry, or something else entirely?"
        ),
    },
    {
        "id": "b",
        "title": "Best TUI Patterns for VM Debuggers",
        "question": (
            "flux-tui needs to feel modern and powerful.  Compare **gdb-like TUI** "
            "(horizontal layout, command-line heritage) with **modern TUIs like "
            "lazygit** (modal, pane-based, keyboard-first).  What interaction "
            "patterns should we adopt?  How should we visualise VM state "
            "(registers, stack, heap, execution trace) in a terminal?  What "
            "prior art should we study?"
        ),
    },
    {
        "id": "c",
        "title": "Expanding Conformance Testing: 20 to 161 Vectors",
        "question": (
            "Our conformance test suite currently covers **20 vectors**.  The "
            "target is **161**.  How do we get there efficiently?  What "
            "categories of tests should we add?  Should we use property-based "
            "testing, fuzzing, differential testing across runtimes, or "
            "formal ISA specification testing?  How do we prevent regression "
            "as the vector count grows?"
        ),
    },
    {
        "id": "d",
        "title": "ISA v2 / v3 Migration Strategy",
        "question": (
            "ISA v2 introduces a **register-based** execution model.  ISA v3 adds "
            "**escape-prefix opcodes** and **instruction compression**.  How "
            "should the debugger handle multiple ISA versions simultaneously?  "
            "What does the migration path look like for existing flux programs?  "
            "How do we version the opcode table without breaking existing runtimes?"
        ),
    },
    {
        "id": "e",
        "title": "Making flux-tui the Fleet's Canonical Debugging Tool",
        "question": (
            "We want flux-tui to become the **single canonical debugger** for "
            "the entire FLUX fleet (9 agents, 912+ repos).  What features are "
            "missing to achieve that?  How should we handle remote debugging, "
            "core-dump analysis, and multi-agent trace correlation?  What "
            "integration points (API, CLI, LSP, DAP) should we support?"
        ),
    },
]

ROLE_NAMES = ["Architect", "VM Engineer", "QA Lead", "Fleet Coordinator", "DevOps"]


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def _headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}


def call_deepseek(
    model: str,
    system_prompt: str,
    user_prompt: str,
    *,
    max_tokens: int = 2048,
    temperature: float = 0.7,
    timeout: float = 90.0,
) -> dict[str, Any]:
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
                timeout=timeout,
            )
            latency = time.monotonic() - start

            if resp.status_code == 429:
                wait = RETRY_BACKOFF * attempt
                print(f"    Rate-limited; waiting {wait}s …", flush=True)
                time.sleep(wait)
                continue

            resp.raise_for_status()
            body = resp.json()
            body["_latency_s"] = latency
            return body

        except httpx.HTTPStatusError as exc:
            print(f"    HTTP {exc.response.status_code} (attempt {attempt}/{MAX_RETRIES})")
            if attempt == MAX_RETRIES:
                raise
            time.sleep(RETRY_BACKOFF * attempt)

        except httpx.RequestError as exc:
            print(f"    Network error: {exc} (attempt {attempt}/{MAX_RETRIES})")
            if attempt == MAX_RETRIES:
                raise
            time.sleep(RETRY_BACKOFF * attempt)

    raise RuntimeError("Unreachable")


def get_usage(body: dict[str, Any]) -> dict[str, int]:
    u = body.get("usage", {})
    return {
        "prompt_tokens": u.get("prompt_tokens", 0),
        "completion_tokens": u.get("completion_tokens", 0),
        "total_tokens": u.get("total_tokens", 0),
        "reasoning_tokens": u.get("reasoning_tokens", 0),
    }


def get_text(body: dict[str, Any]) -> str:
    return body["choices"][0]["message"]["content"].strip()


# ---------------------------------------------------------------------------
# Discussion logic
# ---------------------------------------------------------------------------

def discuss_topic(topic: dict[str, str]) -> tuple[list[RoleResponse], CallRecord]:
    """One API call simulating all 5 roles for a topic."""
    system = (
        f"You are a roundtable facilitator simulating a multi-role discussion.\n\n"
        f"{FLEET_CONTEXT}\n\n"
        f"{ROLE_PROFILES}\n\n"
        f"Instructions:\n"
        f"- Have ALL FIVE participants respond to the discussion topic.\n"
        f"- Each role writes exactly 2 paragraphs from their unique perspective.\n"
        f"- Separate each role with the EXACT marker: ### ROLE: [Role Name]\n"
        f"- Use these exact names: Architect, VM Engineer, QA Lead, Fleet Coordinator, DevOps\n"
        f"- Be specific: reference real tools, patterns, and concrete actions.\n"
        f"- Do NOT add preamble or closing remarks — just the role responses."
    )

    user = f"## Discussion Topic: {topic['title']}\n\n{topic['question']}"

    body = call_deepseek("deepseek-chat", system, user, max_tokens=2048, timeout=90.0)
    text = get_text(body)
    usage = get_usage(body)
    latency = body.get("_latency_s", 0)

    record = CallRecord(
        label=f"topic-{topic['id']}",
        model="deepseek-chat",
        latency_s=latency,
        **usage,
    )

    # Parse role responses
    responses: list[RoleResponse] = []
    parts = re.split(r"###\s*ROLE:\s*(.+?)(?:\n|$)", text)
    for i in range(1, len(parts) - 1, 2):
        name = parts[i].strip()
        content = parts[i + 1].strip()
        if name in ROLE_NAMES or any(n.lower() in name.lower() for n in ROLE_NAMES):
            # Match to canonical name
            for rn in ROLE_NAMES:
                if rn.lower() in name.lower():
                    name = rn
                    break
            responses.append(RoleResponse(role=name, model="deepseek-chat", text=content))

    if not responses:
        # Fallback: split by numbered/bulleted roles
        blocks = re.split(r"(?:\d+\.\s*\*\*|-\s*\*\*)(.+?)\*\*:?", text)
        for i in range(1, len(blocks) - 1, 2):
            name = blocks[i].strip()
            content = blocks[i + 1].strip()
            for rn in ROLE_NAMES:
                if rn.lower() in name.lower():
                    responses.append(RoleResponse(role=rn, model="deepseek-chat", text=content))
                    break

    return responses, record


def synthesize(all_responses: list[RoleResponse]) -> tuple[str, CallRecord]:
    """Architect synthesis using deepseek-reasoner."""
    discussion = "\n\n".join(
        f"**{r.role}**:\n{r.text}" for r in all_responses
    )
    system = (
        "You are the **Architect** — chief synthesiser of the FLUX TUI roundtable.\n"
        "You have deep expertise in debugger architecture, TUI design, and "
        "fleet-scale developer tools.\n\n"
        f"{FLEET_CONTEXT}"
    )
    prompt = (
        "The roundtable is complete. Here is the full transcript:\n\n"
        f"{discussion}\n\n"
        "Produce a **comprehensive synthesis**:\n"
        "1. Top 5-7 **actionable recommendations** (be specific).\n"
        "2. **Consensus vs disagreement** areas.\n"
        "3. **Priority ordering**: P0 (this week), P1 (this quarter), P2 (next quarter).\n"
        "4. **Effort estimates**: S / M / L / XL for each recommendation.\n"
        "5. **Risks and dependencies**.\n"
        "6. **Quick wins** shippable in days.\n\n"
        "Write 6-10 decisive paragraphs."
    )

    body = call_deepseek("deepseek-reasoner", system, prompt, max_tokens=2048, timeout=120.0)
    text = get_text(body)
    usage = get_usage(body)
    latency = body.get("_latency_s", 0)

    record = CallRecord(
        label="synthesis",
        model="deepseek-reasoner",
        latency_s=latency,
        **usage,
    )
    return text, record


# ---------------------------------------------------------------------------
# Markdown output
# ---------------------------------------------------------------------------

def render_markdown(
    topic_data: list[tuple[str, str, list[RoleResponse]]],
    synthesis: str,
    records: list[CallRecord],
    total: TokenUsage,
) -> str:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    L: list[str] = []
    a = L.append

    a("# FLUX TUI Roundtable Simulation\n")
    a(f"**Date:** {ts}  ")
    a(f"**Models:** deepseek-chat (topics) + deepseek-reasoner (synthesis)  ")
    a(f"**Participants:** 5 roles x {len(TOPICS)} topics  ")
    a(f"**Total tokens:** {total.total_tokens:,}  ")
    a(f"(prompt: {total.prompt_tokens:,}, completion: {total.completion_tokens:,}, "
       f"reasoning: {total.reasoning_tokens:,})\n")
    a("---\n")

    for tid, title, responses in topic_data:
        a(f"## Topic {tid.upper()}: {title}\n")
        for r in responses:
            ts_role = datetime.now(timezone.utc).strftime("%H:%M:%S UTC")
            a(f"### [{r.role}]  *(model: {r.model})*")
            a(f"> *{ts_role}*\n")
            a(r.text)
            a("")
        a("---\n")

    a("## Architect's Synthesis  -- Actionable Recommendations\n")
    a(f"> *{datetime.now(timezone.utc).strftime('%H:%M:%S UTC')}*\n")
    a(synthesis)
    a("\n---\n")

    a("## Token Usage & Latency\n")
    a("| Call | Model | Prompt | Completion | Reasoning | Latency (s) |")
    a("|------|-------|--------|------------|-----------|-------------|")
    for r in records:
        a(f"| {r.label} | {r.model} | {r.prompt_tokens} | "
          f"{r.completion_tokens} | {r.reasoning_tokens} | {r.latency_s:.1f} |")
    a("")

    return "\n".join(L)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print("=" * 60)
    print("  FLUX TUI ROUNDTABLE SIMULATION")
    print(f"  Output -> {OUTPUT_FILE}")
    print("=" * 60)

    total = TokenUsage()
    records: list[CallRecord] = []
    topic_data: list[tuple[str, str, list[RoleResponse]]] = []
    all_flat: list[RoleResponse] = []

    # Run all 5 topic calls in parallel
    print(f"\n  Running {len(TOPICS)} topic discussions in parallel …", flush=True)
    results: dict[str, tuple[list[RoleResponse], CallRecord]] = {}
    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = {pool.submit(discuss_topic, t): t for t in TOPICS}
        for future in as_completed(futures):
            topic = futures[future]
            try:
                responses, record = future.result()
                results[topic["id"]] = (responses, record)
                total.merge(vars(record))
                records.append(record)
                topic_data.append((topic["id"], topic["title"], responses))
                all_flat.extend(responses)
                print(f"    [{topic['id'].upper()}] {len(responses)} roles, "
                      f"{record.latency_s:.1f}s, {record.total_tokens} tok")
            except Exception as exc:
                print(f"    [{topic['id'].upper()}] FAILED: {exc}")
                records.append(CallRecord(f"topic-{topic['id']}", "error", 0, 0, 0, 0, 0))

    # Synthesis
    print(f"\n  [SYNTH] Architect synthesising …", flush=True)
    try:
        synth_text, synth_record = synthesize(all_flat)
        total.merge(vars(synth_record))
        records.append(synth_record)
        print(f"    -> {synth_record.latency_s:.1f}s, {synth_record.total_tokens} tokens")
    except Exception as exc:
        print(f"    FAILED: {exc}")
        synth_text = f"*Synthesis failed: {exc}*"
        records.append(CallRecord("synthesis", "error", 0, 0, 0, 0, 0))

    # Save
    md = render_markdown(topic_data, synth_text, records, total)
    OUTPUT_FILE.write_text(md, encoding="utf-8")

    print(f"\n  DONE: {OUTPUT_FILE}")
    print(f"  Tokens: {total.total_tokens:,}")
    print(f"  Calls:  {len(records)}")
    print(f"  Time:   {sum(r.latency_s for r in records):.1f}s")


if __name__ == "__main__":
    main()
