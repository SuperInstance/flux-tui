# 💡 FLUX TUI Brainstorm — 10 Creative Improvements

**Date:** 2026-04-14 21:11:56 UTC
**Models:** deepseek-reasoner (ideation) + deepseek-chat (implementation)
**Total tokens:** 14,854
**Total time:** 244.9s

---

## Summary Table

| # | Idea | Impact | Effort | Priority |
|---|------|--------|--------|----------|
| 1 | Fleet-Wide Live Execution Map | 9/10 | 8/10 | ⭐ 1.1 |
| 2 | AI Conformance Gap Analyzer | 8/10 | 7/10 | ⭐ 1.1 |
| 3 | Time-Traveling Comparative Debug | 8/10 | 9/10 | 📌 0.9 |
| 4 | Semantic Stack/Register Lens | 7/10 | 6/10 | ⭐ 1.2 |
| 5 | SuperInstance-Integrated Breakpoints | 10/10 | 9/10 | ⭐ 1.1 |
| 6 | Holographic Bytecode Disassembly | 7/10 | 7/10 | ⭐ 1.0 |
| 7 | Automated Bisect via Debug Session | 8/10 | 8/10 | ⭐ 1.0 |
| 8 | Collaborative Debugging Sessions | 6/10 | 5/10 | ⭐ 1.2 |
| 9 | Predictive State Visualization | 8/10 | 9/10 | 📌 0.9 |
| 10 | Unified ISA Version Emulation | 9/10 | 8/10 | ⭐ 1.1 |

---

## Idea 1: Fleet-Wide Live Execution Map

**Impact:** 🔴🔴🔴🔴🟡 9/10  
**Effort:** 🔴🔴🔴🔴 8/10

### 🧠 Vision (deepseek-reasoner)

Visualizes real-time FLUX VM executions across all 912+ repos and 9 agents as a network graph within the TUI. Click any node to attach the debugger to that live session. Transforms the tool from a single-instance debugger into a fleet observability cockpit.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll add a new `fleet` module in `src/fleet/` with three core components:
- **`FleetMonitor`**: A singleton that polls the SuperInstance's REST API (likely at `/api/v1/executions`) for active VM sessions. It maintains an `Arc<Mutex<HashMap<ExecutionId, ExecutionMetadata>>>` where metadata includes repo path, agent ID, timestamp, and WebSocket debug port.
- **`LiveMapView`**: A new TUI widget (`ratatui`-based) that renders executions as a force-directed graph using nodes (repos/agents) and edges (execution sessions). We'll use `petgraph` for graph algorithms and `crossterm` for mouse interaction.
- **`SessionAttacher`**: Handles the debugger attachment via WebSocket. When a node is clicked, we spawn a new debugger session connecting to `ws://<agent-ip>:<debug-port>/stream`.

The main `App` struct in `src/app.rs` will gain a new `AppMode::FleetMap` state, and we'll modify the event loop to handle fleet polling intervals (every 2s) and mouse clicks on graph nodes.

## 2. Dependencies
Add to `Cargo.toml`:
- `reqwest` (with `tokio` runtime) for polling SuperInstance API
- `tokio-tungstenite` for WebSocket debugger connections  
- `petgraph` (0.6) for graph data structures and layout algorithms
- `serde_json` for API response parsing
- `chrono` for execution timestamps

No external tools needed—this assumes the SuperInstance already exposes the necessary API endpoints and each FLUX VM runtime has WebSocket debugging enabled (standard in our fleet).

## 3. First Iteration (1 Sprint MVP)
Ship a **read-only visualization** that:
- Polls a mock API endpoint (local JSON file) showing 5–10 simulated executions
- Renders a simple node-link diagram where nodes are labeled with repo names
- Supports `Tab` key to cycle through nodes (mouse interaction comes later)
- Pressing `Enter` on a selected node prints connection details to log (not actual attachment)

Files to create:
- `src/fleet/mod.rs` (module root)
- `src/fleet/mock_api.rs` (hardcoded test data)
- `src/fleet/graph_widget.rs` (basic graph rendering using `ratatui` shapes)
- `src/fleet/types.rs` (ExecutionId, ExecutionMetadata structs)

This gives us the UI skeleton and data flow without live integration risks.

## 4. Testing Approach
- **Unit tests**: Mock API client with predefined execution snapshots; verify graph node count matches.
- **Integration test**: End-to-end test with a local `flux-rs` VM spawned in debug mode, ensuring the TUI can discover it via mock SuperInstance response.
- **Visual regression**: Use `ratatui`'s `TestBackend` to capture buffer states for different graph layouts.
- **Conformance**: Ensure existing debugger tests still pass (attachment logic unchanged).

We'll add a new test binary `cargo test --features fleet-mock` that runs the fleet module tests independently.

## 5. Risks & Unknowns
**Major risks**:
1. **SuperInstance API doesn't exist yet** — we're assuming endpoint design. Mitigation: Work with infra team to spec the API during sprint 0.
2. **WebSocket protocol mismatch** — different FLUX runtimes may have different debug wire formats. Mitigation: Abstract connection behind a `DebugTransport` trait.
3. **Performance with 900+ repos** — force-directed layout may choke. Mitigation: Use `petgraph`'s `spring` layout with fixed iterations; cluster by agent.

**Unknowns**:
- How to authenticate to SuperInstance from within TUI (OAuth? API key?)
- Network partitioning scenarios — what happens when an agent goes offline mid-debug?
- Mouse support in various terminal emulators (fallback to keyboard navigation).

The first iteration deliberately avoids these unknowns by using mock data and keyboard-only interaction.

---

## Idea 2: AI Conformance Gap Analyzer

**Impact:** 🔴🔴🔴🔴 8/10  
**Effort:** 🔴🔴🔴🟡 7/10

### 🧠 Vision (deepseek-reasoner)

Integrates an LLM to analyze debugged FLUX bytecode against the 161 target conformance vectors. It highlights untested behaviors and suggests minimal test programs to close coverage gaps, accelerating validation for all four runtime implementations.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll add three new modules to `flux-tui`:
- `src/analysis/conformance_gap.rs` – Core gap detection logic
- `src/analysis/test_suggestion.rs` – LLM integration for test generation  
- `src/ui/panels/conformance_gap.rs` – TUI panel for displaying results

Key data structure changes:
- Extend `src/vm/state.rs`'s `ExecutionTrace` to track which conformance vectors were exercised during debugging sessions
- Add `ConformanceCoverage` struct mapping vector IDs to `(hit_count, last_seen_pc)` 
- Create `GapAnalysisReport` with `missing_vectors: Vec<ConformanceVector>`, `suggested_tests: Vec<TestSuggestion>`

The analyzer hooks into the existing debugger event system via `src/events.rs`, subscribing to instruction execution and memory access events to build coverage data.

## 2. Dependencies
Add these crates to `Cargo.toml`:
- `reqwest` (async, already in tree) – for LLM API calls
- `serde_json` (already in tree) – for structuring LLM prompts/responses
- `async-openai` (new) – clean OpenAI integration, though we'll abstract behind a trait for multi-provider support
- `ignore` (new) – for scanning test directories to avoid suggesting duplicate tests

External dependencies:
- OpenAI API key (via environment variable `OPENAI_API_KEY`)
- Local conformance vector definitions from `flux-specs` repo (git submodule)
- Optional: Local LLM via Ollama for offline use (future iteration)

## 3. First Iteration (MVP)
Ship in 1 sprint: **Offline gap detection only** – no LLM integration yet.

MVP workflow:
1. During debug session, track which conformance vectors are exercised via simple pattern matching against known vector behaviors
2. Add `:conformance-gap` command to TUI that:
   - Loads vector definitions from `flux-specs/conformance/vectors.yaml`
   - Compares against exercised vectors
   - Displays simple list of missing vector IDs with descriptions
3. Export results to JSON for manual analysis

This gives immediate value (visibility into coverage) without LLM complexity. The UI panel shows:
```
Conformance Gaps (42/161 covered)
┌────┬─────────────────────────────────────────────┐
│ ID │ Description                                 │
├────┼─────────────────────────────────────────────┤
│ 23 │ DIV by zero trap handling                   │
│ 47 │ Memory-mapped I/O page faults               │
│ 89 │ Floating-point denormal underflow           │
└────┴─────────────────────────────────────────────┘
```

## 4. Testing Approach
- **Unit tests**: Mock execution traces, verify gap detection logic in `conformance_gap.rs`
- **Integration test**: Run actual FLUX test programs through debugger, verify coverage tracking
- **Golden tests**: Compare generated gap reports against expected output for known bytecode
- **LLM integration tests** (future): Mock HTTP responses using `wiremock` to test prompt formatting and response parsing without actual API calls

Critical test: Ensure we don't double-count vectors when same behavior is exercised multiple ways.

## 5. Risks & Unknowns
**Primary risks:**
1. **Performance overhead**: Tracking 161 vectors per instruction could slow debugging. Mitigation: Use bitmask representation and only check on specific opcodes.
2. **Vector definition drift**: If `flux-specs` repo changes format, our parser breaks. Mitigation: Use schema validation with `schemars` crate.
3. **LLM cost/quality**: Unpredictable API costs and test quality. Mitigation: Cache suggestions, rate limit, and implement fallback to template-based suggestions.
4. **False positives**: Simple pattern matching may miss edge cases. Mitigation: Start with conservative matching, expand based on runtime team feedback.

**Unknowns:**
- How to uniquely identify when a vector is "fully" covered vs "partially" exercised
- Whether all four runtime implementations have identical conformance requirements
- Optimal prompt engineering for generating minimal, valid FLUX test programs

The MVP de-risks by delivering the core value (gap visibility) without LLM dependencies, while establishing the data collection foundation for future AI enhancements.

---

## Idea 3: Time-Traveling Comparative Debug

**Impact:** 🔴🔴🔴🔴 8/10  
**Effort:** 🔴🔴🔴🔴🟡 9/10

### 🧠 Vision (deepseek-reasoner)

Records non-deterministic VM executions. Allows developers to rewind and compare two different executions of the same program (e.g., from different agents) side-by-side to pinpoint where and why behavioral divergences occurred.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll add three core components to `flux-tui`:

**Recording Layer (`src/recording/`)**:
- `trace.rs`: Defines `ExecutionTrace` struct containing vector of `StepSnapshot` (VM register state, stack, memory pages, PC, timestamp).
- `recorder.rs`: `TraceRecorder` that hooks into VM execution loop via callback interface, capturing snapshots at configurable intervals (every N instructions or on specific events).
- `storage.rs`: `TraceStorage` with SQLite backend (`.traces.db`) storing traces indexed by (program_hash, agent_id, timestamp).

**Comparative Debug UI (`src/ui/comparative/`)**:
- `diff_view.rs`: Dual-pane TUI widget showing side-by-side execution states with visual diffs (using `ratatui` + `tui-textarea`).
- `timeline.rs`: Scrollable timeline control to synchronize playback position across both traces.
- New `ComparativeMode` in main application state, activated via `Ctrl+D` shortcut.

**Trace Management (`src/commands/trace.rs`)**:
- CLI commands: `flux-tui record --output trace.bin`, `flux-tui compare trace1.bin trace2.bin`.
- Integration with SuperInstance API (`superinstance-client` crate) to fetch traces from different agents.

Modified existing structures:
- `src/vm/debugger.rs`: Add `on_step` callback registration for trace recording.
- `src/state.rs`: Extend `AppState` with `TraceState` containing loaded traces and comparison metadata.

## 2. Dependencies
Add to `Cargo.toml`:
```toml
[dependencies]
rusqlite = "0.31"  # Trace storage
serde = { version = "1.0", features = ["derive"] }  # Trace serialization
bincode = "1.3"    # Binary trace format
superinstance-client = "0.1"  # Fetch traces from fleet (internal crate)
difflib = "0.1"    # For state diff visualization
```

External tools:
- SQLite3 (runtime dependency, already common on dev systems)
- SuperInstance gRPC endpoint (requires fleet connectivity for remote traces)

## 3. First Iteration (1 Sprint MVP)
**Local deterministic comparison only**:
- Record traces to simple binary files (`.flux-trace`) using `bincode` serialization
- Basic TUI with:
  - Left/right panes showing VM state at same step index
  - `J/K` to step forward/backward synchronously
  - Highlight differences in register values (red/green)
  - Memory diff limited to first 256 bytes
- No network integration, no SQLite storage
- Manual trace capture via `--record` flag during normal debug session

**Files to create** (≈400-500 lines total):
```
src/recording/
├── mod.rs
├── trace.rs          # StepSnapshot, ExecutionTrace
└── recorder.rs       # Basic recorder with interval sampling
src/ui/comparative/
├── mod.rs
└── diff_view.rs      # Dual-pane widget
```

**Modified files**:
- `src/main.rs`: Add `--record` and `--compare` CLI args
- `src/app.rs`: Add comparative mode toggle and rendering
- `src/vm/debugger.rs`: Add recording callback

## 4. Testing Approach
**Unit tests**:
- `recording/trace.rs`: Verify serialization round-trip for `ExecutionTrace`
- `recording/recorder.rs`: Test snapshot capture at correct intervals
- Mock VM state to ensure memory/register capture works

**Integration tests**:
- Record known deterministic program (e.g., factorial calculation)
- Replay and verify states match at each step
- Compare two identical traces → should show zero differences
- Compare traces with intentional divergence (e.g., modified input) → should highlight first differing step

**Conformance suite**:
- Extend existing 20 conformance vectors to include trace recording
- Add 2-3 comparative debugging specific tests using `flux-tui test` subcommand

**Manual testing**:
- Use `examples/divergence.flux` (to be created) with two slightly different inputs
- Verify TUI navigation and diff highlighting works as expected

## 5. Risks
**Performance overhead**:
- Capturing full VM state every instruction could 10x slowdown
- *Mitigation*: First iteration samples every 100 instructions; use configurable sampling rate

**Storage explosion**:
- A 1M instruction trace with full memory could be gigabytes
- *Mitigation*: MVP stores only registers + small memory window; compression in v2

**Non-determinism capture gaps**:
- External I/O, random

---

## Idea 4: Semantic Stack/Register Lens

**Impact:** 🔴🔴🔴🟡 7/10  
**Effort:** 🔴🔴🔴 6/10

### 🧠 Vision (deepseek-reasoner)

Moves beyond raw values. Plugins can attach semantic annotations (e.g., "This stack value is a file descriptor," "This register holds a UTF-8 string pointer") that are displayed inline. Adapts automatically between ISA v1 (stack) and v2/v3 (registers).

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture

We'll add a `semantics` module in `flux-tui/src/debugger/` with three core components:

**Data Structures:**
- `SemanticAnnotation` enum in `semantics/types.rs`:
```rust
pub enum SemanticAnnotation {
    FileDescriptor(i32),
    Utf8StringPtr { addr: u64, len: Option<usize> },
    HeapAllocation { base: u64, size: usize },
    TypeTag { type_id: u32 },
    Custom { plugin_id: &'static str, data: Vec<u8> }
}
```

- `AnnotationRegistry` in `semantics/registry.rs`: A thread-safe map from `(address, value_index)` to `Vec<SemanticAnnotation>`, where `value_index` is stack offset for v1 or register ID for v2/v3.

**Plugin System:**
- `PluginTrait` in `semantics/plugin.rs` with `analyze_frame(&self, frame: &VmFrame) -> Vec<Annotation>`.
- `PluginManager` that loads dynamic libraries (`.so`/`.dylib`) from `~/.flux/plugins/`.

**Display Integration:**
- Modify `ui/stack_view.rs` and `ui/register_view.rs` to query the registry and append annotations inline: `0x7f34 "fd: 3"` or `R1 → "Hello" (utf8)`.

## 2. Dependencies

Add to `Cargo.toml`:
```toml
[dependencies]
libloading = "0.8"  # For dynamic plugin loading
serde = { version = "1.0", features = ["derive"] }  # For annotation serialization
parking_lot = "0.12"  # For RwLock in registry
```

No external tools required. The plugin API will be versioned (`semantics_api_v1`) to maintain compatibility across flux-tui updates.

## 3. First Iteration (1 Sprint)

**MVP Scope:**
1. Implement `AnnotationRegistry` with in-memory storage (no persistence).
2. Add `#[derive(SemanticPlugin)]` procedural macro for trivial plugins:
   ```rust
   #[derive(SemanticPlugin)]
   struct FdPlugin;
   impl Plugin for FdPlugin {
       fn analyze(&self, frame: &VmFrame) -> Vec<Annotation> {
           // Simple heuristic: values 0-1024 in syscall context are FDs
           vec![]
       }
   }
   ```
3. Modify only the stack view to show annotations in a muted color after raw values.
4. Ship with two built-in plugins: `FdDetector` and `StringDetector` (looks for valid UTF-8 in memory).

**Files Changed:**
- `src/debugger/semantics/` (new directory)
- `src/ui/stack_view.rs` (~50 lines modified)
- `Cargo.toml` and `build.rs` (for proc-macro)

## 4. Testing Approach

**Unit Tests:**
- `cargo test semantics_registry` tests concurrent insert/lookup.
- `cargo test fd_plugin` verifies FD detection in mock frames.

**Integration Test:**
- `tests/integration/semantic_lens.rs` runs flux-tui in headless mode against a known binary (e.g., `test_programs/fd_echo.flux`), captures output, and asserts annotations appear.

**Conformance Vectors:**
- Extend 2 of the 20 existing conformance vectors to include annotation verification.
- Add 1 new vector specifically for semantic lens (e.g., `conformance/annotations/fd_detection.flux`).

## 5. Risks

**Performance:** Annotations queried every UI refresh (60Hz). Registry lookups must be O(1). Unknown: Plugin analysis cost on large frames. Mitigation: Timeout plugins after 1ms.

**ISA Versioning:** v1 (stack) vs v2/v3 (registers) require different `value_index` mapping. Risk: Annotations incorrectly map between ISA versions. Mitigation: Abstract `FrameLocation` enum that handles translation.

**Plugin Stability:** Dynamic loading can crash flux-tui if plugins panic. Mitigation: Isolate plugins in separate threads with panic boundaries; blacklist crashing plugins.

**Unknown:** How to handle overlapping/conflicting annotations from multiple plugins. MVP solution: First-wins; later: priority system.

This plan delivers tangible value in one sprint (inline FD/string hints) while establishing the architecture for future expansion.

---

## Idea 5: SuperInstance-Integrated Breakpoints

**Impact:** 🔴🔴🔴🔴🔴 10/10  
**Effort:** 🔴🔴🔴🔴🟡 9/10

### 🧠 Vision (deepseek-reasoner)

Set a conditional breakpoint in flux-tui that deploys fleet-wide. The SuperInstance monitors all agents and repositories, and the debugger automatically attaches when any instance in the fleet hits the condition. For debugging emergent, fleet-scale issues.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture

We'll add three main components to flux-tui and extend the SuperInstance API. In flux-tui, create `src/fleet/` with:
- `breakpoint_manager.rs`: Manages fleet breakpoints with a `FleetBreakpoint` struct containing `condition: String`, `enabled: bool`, `hit_count: usize`, and `agent_filter: Option<Vec<String>>`
- `superinstance_client.rs`: Handles gRPC communication using tonic, with `set_fleet_breakpoint()` and `poll_breakpoint_hits()` methods
- `fleet_ui.rs`: New TUI panel showing active fleet breakpoints and hits

The SuperInstance needs a new gRPC service in `superinstance/api/v1/debugger.proto` with `FleetBreakpoint` message and `BreakpointHit` notification. Internally, it will maintain a `FleetBreakpointRegistry` that agents can query via existing health-check endpoints.

## 2. Dependencies

Add to flux-tui's Cargo.toml:
- `tonic = "0.11"` (gRPC client)
- `tokio = { version = "1.37", features = ["rt", "sync"] }` (async runtime)
- `serde = { version = "1.0", features = ["derive"] }` (serialization)
- `prost = "0.12"` (protobuf)

The SuperInstance already uses tonic, so we'll extend its existing proto definitions. No new external tools required beyond the existing agent monitoring infrastructure.

## 3. First Iteration

MVP (1 sprint): Simple unconditional breakpoint on specific agent only. In flux-tui:
- Add `:fleet-breakpoint <agent-id> <address>` command that sends to SuperInstance
- SuperInstance forwards to specified agent via existing control channel
- When hit, agent notifies SuperInstance, which queues notification
- flux-tui polls every 2 seconds via `poll_breakpoint_hits()`
- Show basic fleet breakpoint panel with agent ID, address, and hit status

This avoids complex condition parsing, fleet-wide deployment, and automatic attachment initially. File structure:
```
flux-tui/src/fleet/
├── mod.rs
├── breakpoint_manager.rs (stores local copy of fleet breakpoints)
└── superinstance_client.rs (simple polling client)
```

## 4. Testing Approach

1. **Unit tests**: Mock tonic client to test breakpoint manager logic
2. **Integration test**: Local test with `flux-tui --test-fleet` flag that spawns a mock SuperInstance (using `mockall`) and dummy agent
3. **Conformance test**: Add to existing 20 conformance vectors - test that breakpoint on known agent at known address triggers
4. **Manual verification**: Use in development with 2-3 known agents running test programs

We'll add a new test binary `tests/fleet_breakpoints.rs` that uses the actual gRPC client against a test SuperInstance instance.

## 5. Risks

**Primary risk**: SuperInstance scalability with polling. If 50+ flux-tui instances poll every 2 seconds, load could be significant. Mitigation: First iteration only allows one active fleet breakpoint per flux-tui instance.

**Unknowns**: Agent-side breakpoint implementation varies across 4 runtime implementations. Some may not support breakpoints at all. Mitigation: First iteration only works with the reference implementation (flux-vm).

**Data races**: Breakpoint hits may arrive while flux-tui is detached. Mitigation: SuperInstance will queue up to 100 hits per breakpoint, dropping older ones.

**Network partitions**: Agents may lose connection to SuperInstance after breakpoint set. Mitigation: Breakpoints automatically expire after 24 hours in SuperInstance registry.

The safest path is to limit first iteration to single-agent, unconditional breakpoints using the existing agent control channels, which gives us end-to-end validation without tackling fleet-scale complexity immediately.

---

## Idea 6: Holographic Bytecode Disassembly

**Impact:** 🔴🔴🔴🟡 7/10  
**Effort:** 🔴🔴🔴🟡 7/10

### 🧠 Vision (deepseek-reasoner)

Renders the FLUX instruction stream in a 3D, navigable "rope" or "tree" directly in the terminal using advanced ASCII/Unicode art. Control flow branches are visually distinct, making complex jumps and loops instantly comprehensible.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture

We'll add a new `holograph` module under `src/` with three core components:
- **`HologramRenderer`**: Main struct that converts bytecode + symbol info into a 3D ASCII representation. It will consume a `Disassembly` object (from existing `disasm` module) and produce a `Hologram` struct containing lines of positioned characters.
- **`NavigationState`**: Tracks viewport position (x,y,z offsets), zoom level, and selected node in the 3D space. Integrates with existing TUI input handling.
- **`BranchMapper`**: Analyzes control flow to identify jumps/loops and assign visual properties (colors, connection characters). Uses existing `ControlFlowAnalyzer` from the debugger core.

Key data structure additions:
- `src/holograph/hologram.rs`: `Hologram { nodes: Vec<Node>, connections: Vec<Connection> }` where `Node` contains `position: (i32, i32, i32)`, `text: String`, `instr_addr: u64`.
- Modified `src/ui/mod.rs` to add a `HologramView` component that can be toggled via `F7` key, replacing the standard disassembly view.

## 2. Dependencies

We'll add two carefully chosen crates to `Cargo.toml`:
- **`crossterm`** (already present): We'll extend its usage for enhanced terminal graphics.
- **`unicode-width`** (already present): For proper character width calculation in mixed Unicode/ASCII art.
- **`tui`** (already present): We'll create a new custom widget in `src/ui/hologram_widget.rs`.

No new external tools or heavy 3D libraries—we're implementing a pseudo-3D projection ourselves using depth cues (brighter foreground for "closer" elements, `│/─/└/├` characters for connections, and simple perspective: `(x', y') = (x + z/2, y + z/2)`).

## 3. First Iteration (MVP for 1 Sprint)

**Week 1**: Implement `BranchMapper` that identifies forward/backward jumps in linear disassembly and builds a tree structure. Create basic `HologramRenderer` that projects this tree to 2D terminal space with:
- Instructions arranged vertically
- Backward jumps shown with `↶` Unicode arrows
- Forward jumps shown with `↷` arrows  
- Loop bodies indented rightward
- Single-character prefixes indicating instruction type (`L`=load, `S`=store, `J`=jump, etc.)

**Week 2**: Integrate with TUI as a toggleable view (`F7`). Add panning with arrow keys and zoom with `+/-`. Ship with known limitations: no true 3D rotation, fixed color scheme, only handles direct jumps (not computed/indirect).

Files created: `src/holograph/{mod.rs, renderer.rs, nav.rs, mapper.rs}`, `src/ui/hologram_widget.rs`.

## 4. Testing Approach

1. **Unit tests** for `BranchMapper` using the existing 20 conformance vectors: verify it correctly identifies all jumps/loops in known bytecode.
2. **Visual regression tests**: Capture terminal output for sample programs and compare against checked-in `.ans` files using `assert_cli` crate (already in dev-dependencies).
3. **Integration test**: Load a simple Fibonacci FLUX program, toggle holographic view, verify navigation works without panics.
4. **Fuzz test** the projection logic with random bytecode to ensure no arithmetic overflows in position calculations.

We'll add a test binary `cargo test --test holograph` that runs all holograph-specific tests.

## 5. Risks

**Primary risk**: Terminal performance with large bytecode (>10k instructions). Our naive O(n²) connection drawing could lag. Mitigation: Implement culling—only render nodes visible in viewport, with incremental rendering.

**Unknown**: How to visually distinguish nested loops 3+ levels deep with only 8 colors. Fallback: use character patterns (`//`, `\\`, `||`, `==`) when color exhausted.

**Integration risk**: The existing disassembly view assumes linear address ordering. Our tree representation may break existing breakpoint/single-step logic. Mitigation: Keep linear address mapping in `Node` struct and translate clicks back to addresses for the debugger core.

**Terminal compatibility**: Some Unicode characters may display incorrectly on older terminals. We'll provide a `--ascii-only` flag that uses `+`, `|`, `-` instead of box-drawing characters.

---

## Idea 7: Automated Bisect via Debug Session

**Impact:** 🔴🔴🔴🔴 8/10  
**Effort:** 🔴🔴🔴🔴 8/10

### 🧠 Vision (deepseek-reasoner)

Records a debug session of a failure. Then, using git history from the relevant repo, the tool automatically performs a semantic bisection, replaying the recorded test against historical commits to identify the exact code change that introduced the bug.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll add three new modules to `flux-tui/src/`:
- `record/` for session capture (serializable `DebugSession` struct containing VM state snapshots, breakpoints, and execution trace)
- `bisect/` for git integration and semantic replay (`GitBisectRunner` with `BisectStrategy` trait)
- `replay/` for VM state restoration (`SessionReplayer` using existing VM runtime)

Key data structure additions:
- `src/record/session.rs`: `DebugSession { metadata: SessionMeta, snapshots: Vec<VmSnapshot>, trace: ExecutionTrace }`
- `src/bisect/strategy.rs`: `BisectResult { commit: GitCommit, is_failing: bool, diff: Option<String> }`
- Modify `src/app.rs` to add `BisectMode` to the `AppState` enum with corresponding UI panel

The session recording hooks into existing debugger events via the `EventHandler` system, serializing to MessagePack (using `rmp-serde`) for compact binary storage.

## 2. Dependencies
Add to `Cargo.toml`:
- `git2` (0.18+): For programmatic git operations
- `rmp-serde` (0.15+): Compact session serialization
- `tempfile` (3.10+): For isolated workspace cloning
- `indicatif` (0.17+): Progress bars for bisect operations

External requirements:
- Git CLI must be available in PATH (fallback if `git2` fails)
- Target repository must have linear-ish history (handled with heuristics)
- Sufficient disk space for temporary clones (~2x repo size)

## 3. First Iteration (MVP for 1 sprint)
Ship a **manual bisect trigger** with **basic recording**:
1. Add "Record Session" button in debugger UI (F7 keybind)
2. Record minimal VM state: program counter, stack, memory regions touched
3. Implement `flux-tui bisect --session session.bin --repo-path ./target` CLI command
4. Bisect runs externally (not in TUI) using simple pass/fail detection via exit code
5. Output: commit hash and brief diff to terminal

This avoids TUI integration complexity initially. The session format is versioned (`v1`) to allow future expansion. We'll support only the current working directory's git repo initially.

## 4. Testing Approach
- **Unit tests**: Mock git repository with synthetic history in `tests/fixtures/`
- **Integration**: Use `flux-tui`'s own repo as test subject (record simple session, bisect dummy change)
- **Conformance**: Ensure recorded sessions replay identically across all 4 FLUX runtime implementations
- **Edge cases**: Test with merge commits, shallow clones, and dirty working directories
- **Validation**: Compare bisect results against `git bisect run` manual runs for known regressions

We'll add a new CI job that runs the bisector against a prepared test repo with intentional breakage at known commit.

## 5. Risks & Unknowns
**Primary risks**:
1. **VM state determinism**: Different runtime implementations may produce subtly different behavior, causing false bisect results. Need strict conformance verification.
2. **Git history complexity**: Merge commits, rebases, and force-pushes break naive bisect. We'll need heuristics to detect nonlinear history.
3. **Performance**: Recording full execution traces for long sessions could consume GBs of memory. MVP limits to 10,000 instructions.
4. **External dependencies**: `git2` crate may have linking issues on some platforms. We'll implement fallback to `std::process::Command` git CLI.
5. **False positives**: Build failures unrelated to the bug (missing dependencies, toolchain changes) could mislead bisect. We'll add simple skip logic for non-compiling commits.

**Mitigation**: Start with opt-in feature flag, extensive logging, and clear warnings about experimental status. The MVP's external CLI mode reduces risk to core TUI stability.

---

## Idea 8: Collaborative Debugging Sessions

**Impact:** 🔴🔴🔴 6/10  
**Effort:** 🔴🔴🟡 5/10

### 🧠 Vision (deepseek-reasoner)

Enables multiple developers to share a debug session in real-time. Each participant has a cursor, with voice/video chat integration (via external tools). Perfect for pair-debugging across the fleet's distributed teams.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll add a `collab/` module with three core components:  
- **SessionManager** (`src/collab/session.rs`): Handles WebSocket connections, participant join/leave, and cursor synchronization. Uses a `HashMap<ParticipantId, CursorState>` where `CursorState` includes `(file_path, line, column, color)`.
- **CursorLayer** (`src/collab/cursor_layer.rs`): A `ratatui::Layer` that renders remote cursors/selection highlights over the existing TUI. Each participant gets a distinct color from `crossterm::style::Color`.
- **NetworkBridge** (`src/collab/network.rs`): Abstracts over `tokio_tungstenite` for WebSocket communication. Messages serialize via `serde_json` with a `CollabMessage` enum (CursorUpdate, BreakpointSync, SessionControl).

The main `App` struct gains a `collab_session: Option<Arc<Mutex<SessionManager>>>` field. The existing debugger state (`VmState`, breakpoints) will need thread-safe wrappers (`Arc<RwLock<>>`) for shared access.

## 2. Dependencies
Add to `Cargo.toml`:
```toml
tokio = { version = "1.37", features = ["rt-multi-thread", "sync"] }
tokio-tungstenite = "0.21"
serde_json = "1.0"
arc-swap = "1.6"  # For lock-free state reads in rendering
```
External integration: We'll document pairing with existing tools (Discord, Zoom) for voice/video—no direct integration initially. For network discovery, we'll use simple invite codes (UUIDs) rather than a centralized directory service.

## 3. First Iteration (1 Sprint MVP)
Ship **cursor synchronization only** with manual WebSocket server setup.  
- New `--collab-ws` flag accepts `ws://host:port` or acts as server on `:port`.  
- Participants see others' cursors as colored `█` blocks in the source view.  
- No breakpoint/state sync yet.  
- Implementation: ~500 lines across 3 new files + modifications to `src/app.rs` and `src/main.rs` for flag parsing and session initialization.  
- The MVP uses a single shared thread for network I/O via `tokio::spawn` without blocking the TUI event loop.

## 4. Testing Approach
- **Unit tests**: Mock WebSocket connections using `tokio::test`; verify cursor state updates.  
- **Integration test**: A Python script (`tests/collab_integration.py`) spawns two `flux-tui` instances connected to a test WebSocket server, verifies cursor propagation.  
- **Concurrency testing**: Use `loom` to check thread safety of `Arc<RwLock<VmState>>` accesses.  
- **Manual validation**: Document a "pair debugging" recipe using `websocat` as a simple relay server.

## 5. Risks & Unknowns
**Network latency** could cause cursor jitter; we'll need debouncing (100ms throttling) in the MVP.  
**Security**: No authentication in MVP—anyone with the WebSocket URL can join. This is acceptable behind VPNs but requires future work.  
**Synchronization complexity**: Breakpoint/state sync (future feature) will require operational transformation (OT) or CRDTs—potentially large scope creep. We'll explicitly exclude this from MVP.  
**TUI performance**: Rendering many remote cursors may slow display; we'll benchmark with 10 concurrent users and implement off-screen cursor culling if needed.

---

## Idea 9: Predictive State Visualization

**Impact:** 🔴🔴🔴🔴 8/10  
**Effort:** 🔴🔴🔴🔴🟡 9/10

### 🧠 Vision (deepseek-reasoner)

An ML model, trained on historical successful executions, runs in the background. It predicts the next N steps of the VM's state (stack/registers) and highlights deviations in real-time, acting as an automated anomaly detector.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll add three new modules to `flux-tui/src/`:
- `predictor/` containing `model.rs` (trait + concrete implementations), `trainer.rs` (offline training), and `infer.rs` (real-time inference)
- `anomaly/` with `detector.rs` (deviation analysis) and `visualizer.rs` (TUI integration)
- `history/` with `recorder.rs` (execution trace collection)

Key data structure changes:
- Extend `VMState` in `src/vm/state.rs` to include a `predicted: Option<VMState>` field
- Add `PredictionContext` struct containing model weights and configuration
- Create `ExecutionTrace` struct in `src/history/mod.rs` to store `(opcode, pre_state, post_state)` tuples

The predictor will hook into the existing debugger loop via the `Event` system in `src/app.rs`, running inference after each step and before UI rendering.

## 2. Dependencies
Add these crates to `Cargo.toml`:
- `tract` or `candle` (for lightweight neural net inference) - `tract` is simpler for initial prototyping
- `serde_json` (for model serialization)
- `ndarray` (for tensor operations)
- `rayon` (for parallel training data processing)
- `indicatif` (for training progress bars)

We'll need Python tooling for initial model prototyping (`scikit-learn` or `pytorch`), but the shipped product will use pure Rust inference. The training pipeline will be a separate binary (`flux-tui-train`) that outputs model weights as `.npz` files.

## 3. First Iteration (MVP)
Ship in 1 sprint: **Static Pattern Detector** using simple statistical models instead of full ML.

Implementation:
- Modify `src/predictor/model.rs` with a `MarkovPredictor` that learns opcode transition probabilities from historical traces
- Add basic anomaly highlighting in `src/ui/state_panel.rs`: color stack values red when they deviate >2σ from historical norms
- Train on the existing 20 conformance vectors, storing patterns in `~/.flux-tui/patterns.json`
- No real-time model updates - just pre-computed statistics

This gives immediate value (detecting unusual opcode sequences) without complex ML infrastructure. The UI change is minimal: add a `[P]` toggle to enable/disable prediction highlights.

## 4. Testing Approach
- **Unit tests**: `cargo test` for `MarkovPredictor` probability calculations
- **Integration test**: Run conformance vectors through debugger with prediction enabled, verify no false positives on known-good traces
- **Golden tests**: Save expected predictions for simple programs (`tests/fixtures/predictor/`)
- **Fuzz testing**: Use `cargo fuzz` to ensure predictor doesn't crash on malformed traces
- **Benchmark**: Ensure inference adds <1ms per step via `criterion` benchmarks

We'll add a CI step that trains on the 20 conformance vectors and verifies the model loads correctly.

## 5. Risks & Unknowns
**Primary risks:**
1. **Performance impact**: Real-time inference could slow debugging. Mitigation: Use extremely simple models (Markov, linear regression) initially, profile with `flamegraph`.
2. **False positives**: Overly sensitive detection annoys users. Mitigation: Make thresholds configurable, add whitelist for known benign patterns.
3. **Model staleness**: Fleet evolves, patterns become outdated. Mitigation: Design model versioning from day one, plan for periodic retraining.
4. **Data collection overhead**: Storing execution traces could bloat memory. Mitigation: Ring buffer with configurable size (default: last 10k steps).
5. **ISA version compatibility**: v2/v3 changes will break models. Mitigation: Abstract model features through `ISAFeatureExtractor` trait.

**Unknown:** Whether simple statistical models will catch meaningful anomalies. We'll validate in sprint 1 before investing in neural approaches.

---

## Idea 10: Unified ISA Version Emulation

**Impact:** 🔴🔴🔴🔴🟡 9/10  
**Effort:** 🔴🔴🔴🔴 8/10

### 🧠 Vision (deepseek-reasoner)

A core feature allowing flux-tui to load and debug bytecode for any ISA version (v1, v2, or v3). It transparently translates and displays state in a canonical form, future-proofing the tool and simplifying cross-version migration.

### 🔧 Implementation Plan (deepseek-chat)

## 1. Architecture
We'll introduce a new `isa` module (`src/isa/mod.rs`) with three core components. First, a `Version` enum (`V1`, `V2`, `V3`) that becomes part of the bytecode metadata. Second, a `Decoder` trait with implementations for each version (`V1Decoder`, etc.) that converts raw bytes to a unified `Instruction` struct. This struct will contain the canonical representation (opcode mnemonic, operands, immediate values) plus version-specific metadata. Third, an `Emulator` trait with `StackEmulator` (v1) and `RegisterEmulator` (v2/v3) implementations that wrap the existing VM state but expose a common `EmulationState` interface (program counter, stack frames, registers displayed as virtual registers). The main `Debugger` struct will gain an `isa_version` field and delegate to the appropriate decoder/emulator. The TUI will only interact with the canonical `EmulationState`.

## 2. Dependencies
We'll add `thiserror` for clean error handling in the ISA module and `serde` (already likely present) for version metadata serialization. No external tools needed. We'll create a soft dependency on the `flux-isa-specs` repository (if it exists) by including its conformance test vectors as git submodules under `tests/fixtures/`. If specs aren't centralized, we'll bundle minimal reference bytecode files for each version. The main integration is internal: the decoder must align with the official ISA documentation (potentially as markdown files in the fleet).

## 3. First Iteration
MVP ships with **V1 full support + V2 decoding only**. We modify `src/binary.rs` to detect version via a magic header (`"FLUX_V1"`, `"FLUX_V2"`) or fallback to V1. The `V2Decoder` translates V2 instructions to the unified `Instruction` format but uses the existing V1 emulator for execution (meaning V2 register ops won't run correctly, but can be stepped through). The TUI displays decoded instructions with a `[V2]` prefix. This gives immediate value: users can inspect V2 bytecode while we build the register emulator. Changes are isolated to ~5 files: binary loading, new `isa` module, and debugger initialization.

## 4. Testing Approach
Three test layers: (1) Unit tests for each decoder using handcrafted bytecode snippets; (2) Integration tests that run conformance vectors (starting with 20 existing V1 vectors) through the emulator and compare final state; (3) "Cross-version snapshot" tests where we compile simple programs (e.g., factorial) to each ISA version and verify the debugger can single-step through them, capturing UI state snapshots. We'll add a `cargo test --features conformance` flag that downloads test vectors if missing. For V2/V3, we'll collaborate with the runtime teams to generate reference bytecode files.

## 5. Risks
The largest risk is **ISA version ambiguity**—bytecode without clear headers may be misidentified. We'll mitigate by requiring an explicit `--isa-version` flag when detection fails. Second, **performance overhead** from emulation indirection; we'll profile with large bytecode files and consider caching decoded basic blocks. Unknowns include V3's compression extensions, which may require streaming decompression. We'll stub these initially with "unsupported opcode" placeholders. Finally, **spec drift**: if ISA specs change independently of flux-tui, conformance tests will break. We'll pin to specific spec commits and add a periodic sync job in CI.

---

## 📊 Prioritisation Matrix

Ideas ranked by **Impact / Effort** ratio (bang-for-buck):

| Rank | Idea | Impact | Effort | I/E Ratio | Recommendation |
|------|------|--------|--------|-----------|----------------|
| 1 | Collaborative Debugging Sessions | 6 | 5 | 1.20 | 🔄 Schedule |
| 2 | Semantic Stack/Register Lens | 7 | 6 | 1.17 | 🔄 Schedule |
| 3 | AI Conformance Gap Analyzer | 8 | 7 | 1.14 | 🔄 Schedule |
| 4 | Fleet-Wide Live Execution Map | 9 | 8 | 1.12 | 🔄 Schedule |
| 5 | Unified ISA Version Emulation | 9 | 8 | 1.12 | 🔄 Schedule |
| 6 | SuperInstance-Integrated Breakpoints | 10 | 9 | 1.11 | 🔄 Schedule |
| 7 | Holographic Bytecode Disassembly | 7 | 7 | 1.00 | 🔄 Schedule |
| 8 | Automated Bisect via Debug Session | 8 | 8 | 1.00 | 🔄 Schedule |
| 9 | Time-Traveling Comparative Debug | 8 | 9 | 0.89 | ⏳ Backlog |
| 10 | Predictive State Visualization | 8 | 9 | 0.89 | ⏳ Backlog |
