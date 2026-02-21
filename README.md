# AI Debate Experiment

A structured debate between AI agents, orchestrated by Claude Code Agent Teams. Specialised
agents — Chair, N configurable Debaters, Reporter, Verifier, Audience, and Assessor — argue a
topic, fact-check each other's sources in real time, and produce a publishable written record.

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

## Running a Debate

### Step 1 — Adjust round settings (optional)

Open `config/debate-config.json` and edit these values if desired:

```json
{
  "min_rounds": 3,
  "max_rounds": 8,
  "time_budget_minutes": 30
}
```

For a quick test run, set `"max_rounds": 1`.

> **Note:** `config/debate-config.json` is a runtime state file. The Chair populates it at startup
> with the topic, debater lineup, and output directory. You do not need to edit `topic`, `debaters`,
> or `output_dir` manually — the Chair handles these.

### Step 2 — Start the debate

From the project directory, launch Claude Code with Agent Teams enabled:

```bash
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions
```

Once the Claude Code prompt appears, **start the debate by stating your topic**:

```
Start the debate. The topic is: Should artificial intelligence be used to make judicial decisions?
```

Or just say `Start the debate.` and the Chair will ask you for the topic.

The Chair reads `CLAUDE.md` automatically when Claude Code starts, so it already knows its role.
Sending "Start the debate." triggers the startup sequence:

1. Extract (or ask for) the topic
2. Propose a debater lineup — **wait for your approval before continuing**
3. Create a timestamped output directory under `output/`
4. Initialise `{output_dir}/debate-log.jsonl`
5. Spawn all debater agents plus Reporter, Verifier, Audience, and Assessor
6. Run the debate through all phases automatically

### Step 3 — Specifying Debaters

You have three ways to tell the Chair who should debate:

**Option 1 — No spec (Chair decides):**
```
Start the debate. The topic is: X.
```
The Chair proposes a contextually appropriate lineup — typically 2 debaters in classic adversarial
format, or 3 if the topic has distinct natural perspectives. You review and approve before
the debate begins.

**Option 2 — Persona hints:**
```
Start the debate. Topic: X. I want a venture capitalist, a labour economist, and an AI safety researcher.
```
The Chair fleshes out each persona with an appropriate starting position and incentives, then
presents the lineup for your approval.

**Option 3 — Specific detail:**
```
Start the debate. Topic: X.
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

### Step 4 — Watch the debate

The Chair narrates progress in its main session. If you have `tmux` available, you can split each
agent into its own pane for full visibility:

```bash
tmux new-session -s debate
export CLAUDE_CODE_SPAWN_BACKEND=tmux
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions
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

### Step 5 — Read the output

When the debate concludes, the Reporter writes all output files to a timestamped directory under
`output/`. For example:

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

## Configuration Reference

`config/debate-config.json` (settable fields — others are populated at runtime):

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

**Runtime-only fields** (do not edit manually):

| Field | Description |
|---|---|
| `topic` | Set by the Chair from your startup message. |
| `output_dir` | Set by the Chair at startup (timestamped path under `output/`). |
| `debaters` | Populated by the Chair after you approve the lineup. Array of `{name, persona, starting_position, incentives, model}` objects. |

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

See `CLAUDE.md` for the complete set of 24 rules.

---

## Project Structure

```
ai-debate/
├── CLAUDE.md                   # Chair instructions + shared rules (read by ALL agents)
├── README.md                   # This file
├── config/
│   └── debate-config.json      # Runtime configuration (populated at startup)
├── prompts/
│   ├── debater.md              # Universal debater agent system prompt
│   ├── promoter.md             # DEPRECATED — superseded by debater.md
│   ├── detractor.md            # DEPRECATED — superseded by debater.md
│   ├── reporter.md             # Reporter agent system prompt
│   ├── verifier.md             # Verifier agent system prompt
│   ├── audience.md             # Audience agent system prompt
│   └── assessor.md             # Assessor agent system prompt
├── shared/
│   └── write-log.sh            # Atomic JSONL writer (used by all agents)
└── output/                     # One subdirectory created per debate run
```

---

## Between Runs

Each debate run creates its own timestamped output directory (e.g.
`output/20260221T140000Z-should-ai-be-used.../`) containing the full debate log and all output
files. No manual cleanup is needed — just start a new debate and a fresh directory is created
automatically.

---

## Troubleshooting

**Agents don't spawn** — ensure `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set before launching.

**`flock: command not found`** — install `util-linux` (Linux) or use `brew install util-linux`
(macOS via Homebrew). On macOS, `flock` is available in util-linux: `brew install util-linux`.

**`write-log.sh` fails with permission error** — ensure the script is executable:
```bash
chmod +x shared/write-log.sh
```

**Debate ends immediately** — check that `min_rounds` and `max_rounds` in config are set to
values greater than 0.

**Blog post not produced** — the Chair declared the debate void (e.g., both sides had fabricated
sources). See `metadata.json` for the `outcome_reason`.
