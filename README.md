# AI Debate — Claude Code Plugin

A structured debate between AI agents, packaged as a Claude Code plugin. Install once, then use
`/debate` from any directory to run a fully orchestrated debate on any topic.

Specialised agents — Chair, N configurable Debaters, Reporter, Verifier, Audience, and Assessor —
argue a topic, fact-check each other's sources in real time, and produce a publishable written
record.

---

## How It Works

| Agent | Role |
|---|---|
| **Chair** | Neutral moderator. Manages turn order, issues rulings, declares the outcome. Proposes the debater lineup and waits for user approval before spawning agents. |
| **Debaters** | N configurable participants, each with their own persona, starting position, and incentives — proposed by the Chair at startup and approved by the user before the debate begins. |
| **Reporter** | Silent observer. Produces the transcript, summary, and blog post at the end. |
| **Verifier** | Async fact-checker. Verifies every cited URL and flags fabricated sources. |
| **Audience** | Engaged observer. Submits clarifying questions mid-debate; gives a final opinion at close. |
| **Assessor** | Post-debate reviewer. Evaluates each agent's performance and produces an improvement report. |

The Chair is the lead Claude Code session. It proposes a debater lineup based on your topic,
waits for your approval, then spawns all agents as teammates and coordinates a structured debate
through opening statements, multiple rebuttal rounds, and closing statements before declaring a
winner.

All debate entries are written to `{output_dir}/debate-log.jsonl` — an append-only log inside
the run's output directory that acts as the shared source of truth for all agents.

---

## Prerequisites

- **Claude Code** installed and authenticated
- **Agent Teams** experimental feature enabled (set the env var below)
- `bash`, `python3`, and `flock` available (standard on macOS and Linux)

---

## Installation

**Via marketplace (recommended):**

```
/plugin marketplace add colings86/ai-debate
/plugin install ai-debate@ai-debate
```

**Directly from a local clone:**

```bash
claude plugin install ./plugins/ai-debate
```

After installation, the `/debate` skill is available in any Claude Code session.

---

## Quick Start

In any Claude Code session (no need to `cd` into the repo):

```bash
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude
```

Then type:

```
/debate
```

The Chair will ask for your topic if you haven't provided one, propose a debater lineup, and wait
for your approval before starting.

Or provide a topic immediately:

```
/debate The topic is: Should artificial intelligence be used to make judicial decisions?
```

---

## Specifying Debaters

You have three ways to tell the Chair who should debate:

**Option 1 — No spec (Chair decides):**
```
/debate The topic is: X.
```
The Chair proposes a contextually appropriate lineup — typically 2 debaters in classic adversarial
format, or 3 if the topic has distinct natural perspectives. You review and approve before
the debate begins.

**Option 2 — Persona hints:**
```
/debate Topic: X. I want a venture capitalist, a labour economist, and an AI safety researcher.
```
The Chair fleshes out each persona with an appropriate starting position and incentives, then
presents the lineup for your approval.

**Option 3 — Specific detail:**
```
/debate Topic: X.
Debater 1: venture-capitalist — argues AI is net positive for employment; incentivised by growth narratives.
Debater 2: labour-economist — argues structural unemployment is underappreciated; incentivised by worker welfare data.
```
The Chair uses your specifications directly, filling in any gaps you leave.

**Modifying the proposed lineup:**
After the Chair presents its proposal, you can reply "Can you make the second debater more
sceptical, focused on data quality issues?" and the Chair will revise and re-present before
proceeding.

> **Debater name constraint:** Names must be alphanumeric plus hyphens only (e.g., `venture-capitalist`,
> `labour-economist`). The Chair handles this automatically.

---

## Watching the Debate

The Chair narrates progress in its main session. If you have `tmux` available, you can split each
agent into its own pane for full visibility:

```bash
tmux new-session -s debate
export CLAUDE_CODE_SPAWN_BACKEND=tmux
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude
```

You can also tail the debate log in another terminal (substitute your run's output directory):

```bash
tail -f output/<timestamp>-<slug>/debate-log.jsonl | python3 -c "
import sys, json
for line in sys.stdin:
    e = json.loads(line)
    print(f'[{e[\"seq\"]}] {e[\"speaker\"]}: {e[\"type\"]} — {e[\"content\"][:80]}')
"
```

---

## Reading the Output

When the debate concludes, the Reporter writes all output files to a timestamped directory under
`output/` in your **current working directory**. For example:

```
output/20260221T140000Z-should-ai-be-used-in-judicial-sent/
├── transcript.md       # Full debate record with redaction markers
├── summary.md          # Key arguments and debate flow
├── blog-post.md        # 800–1500 word journalistic piece (omitted if debate is void)
├── metadata.json       # Run metadata: outcome, times, verification stats
├── debate-log.jsonl    # Copy of the shared log for archiving
└── assessor-report.md  # Post-debate process review and improvement suggestions
```

---

## Configuration

Debate settings can be customised at three levels. Later levels override earlier ones:

| Level | Location | Use case |
|---|---|---|
| Built-in defaults | `${PLUGIN_ROOT}/config-template.json` | Plugin defaults — not edited by users |
| User defaults | `~/.claude/ai-debate.json` | Your personal preferences across all projects |
| Project config | `.claude/ai-debate.json` | Per-project settings (commit this to source control) |
| Local overrides | `.claude/ai-debate.local.json` | Per-machine overrides (add to `.gitignore`) |

**Configurable fields:**

| Field | Default | Description |
|---|---|---|
| `min_rounds` | `3` | Minimum rebuttal rounds before the Chair may end the debate. |
| `max_rounds` | `8` | Hard cap on rebuttal rounds. |
| `time_budget_minutes` | `30` | Soft time limit. Chair may conclude early if exceeded. |
| `models.chair` | `claude-opus-4-6` | Model for the Chair agent. |
| `models.reporter` | `claude-sonnet-4-6` | Model for the Reporter agent (also used as the default debater model). |
| `models.verifier` | `claude-sonnet-4-6` | Model for the Verifier agent. |
| `models.audience` | `claude-sonnet-4-6` | Model for the Audience agent. |
| `models.assessor` | `claude-sonnet-4-6` | Model for the Assessor agent. |

**Example — minimal project config** (`.claude/ai-debate.json`):

```json
{
  "max_rounds": 2
}
```

**Example — user defaults** (`~/.claude/ai-debate.json`):

```json
{
  "min_rounds": 2,
  "max_rounds": 5,
  "time_budget_minutes": 20
}
```

> **Note:** `.claude/ai-debate.local.json` should be added to `.gitignore` since it contains
> per-machine overrides that shouldn't be shared.

**Runtime fields** (`topic`, `output_dir`, `debaters`) are never stored in config files —
the Chair derives them from your startup message and passes them directly to agents at runtime.

---

## Debate Rules (Summary)

- All factual claims **must** cite a real, accessible URL. Fabricated URLs result in immediate
  disqualification of that argument.
- Speculative arguments must be explicitly labelled `[CONJECTURE]`.
- Before logging any figure or statistic, debaters must use `WebFetch` to confirm the exact value
  appears on the cited page (numerical pre-verification).
- The Verifier independently checks cited sources using `WebFetch` and reports any fabrications
  to the Chair urgently.
- The Chair's rulings are final. Redacted entries are struck from the record; the Reporter
  replaces them with `[REDACTED — reason]` markers.
- The Reporter never takes sides. The blog post is suppressed entirely if the debate is declared
  void.

See `plugins/ai-debate/agents/debater.md` for the complete set of 24 rules.

---

## Project Structure

```
ai-debate/
├── .claude-plugin/
│   └── marketplace.json        # Marketplace catalog (lists the plugin)
├── plugins/
│   └── ai-debate/
│       ├── .claude-plugin/
│       │   └── plugin.json     # Plugin manifest
│       ├── skills/
│       │   └── debate/
│       │       └── SKILL.md    # Chair orchestration + /debate entry point
│       ├── agents/
│       │   ├── debater.md      # Universal debater agent (all debaters use this)
│       │   ├── reporter.md     # Reporter agent
│       │   ├── verifier.md     # Verifier agent
│       │   ├── audience.md     # Audience agent
│       │   └── assessor.md     # Assessor agent
│       ├── shared/
│       │   └── write-log.sh    # Atomic JSONL writer (used by all agents via DEBATE_OUTPUT_DIR)
│       └── config-template.json  # Built-in defaults (user-editable fields only)
└── output/                     # One subdirectory created per debate run (in current working dir)
```

---

## Between Runs

Each debate run creates its own timestamped output directory (e.g.
`output/20260221T140000Z-should-ai-be-used.../`) in your **current working directory** containing
the full debate log and all output files. No manual cleanup is needed — just start a new debate
and a fresh directory is created automatically.

---

## Troubleshooting

**`/debate` not found** — ensure the plugin is installed: `claude plugin install ./plugins/ai-debate`

**Agents don't spawn** — ensure `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set before launching.

**`flock: command not found`** — install `util-linux` (Linux) or use `brew install util-linux`
(macOS via Homebrew). On macOS, `flock` is available in util-linux: `brew install util-linux`.

**`write-log.sh` fails with `DEBATE_OUTPUT_DIR not set`** — the agent did not export the env var
from its spawn prompt. This is a startup sequence bug — check the agent's spawn message contains
`DEBATE_OUTPUT_DIR=...`.

**`write-log.sh` fails with permission error** — ensure the script is executable:
```bash
chmod +x plugins/ai-debate/shared/write-log.sh
```

**Debate ends immediately** — check that `min_rounds` and `max_rounds` in your config are set to
values greater than 0.

**Blog post not produced** — the Chair declared the debate void (e.g., both sides had fabricated
sources). See `metadata.json` for the `outcome_reason`.
