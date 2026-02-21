# AI Debate Experiment

A structured debate between AI agents, orchestrated by Claude Code Agent Teams. Five specialised
agents — Chair, Promoter, Detractor, Reporter, and Verifier — argue a topic, fact-check each
other's sources in real time, and produce a publishable written record.

---

## How It Works

| Agent | Role |
|---|---|
| **Chair** | Neutral moderator. Manages turn order, issues rulings, declares the outcome. |
| **Promoter** | Argues the **affirmative** side of the topic. |
| **Detractor** | Argues the **negative** side of the topic. |
| **Reporter** | Silent observer. Produces the transcript, summary, and blog post at the end. |
| **Verifier** | Async fact-checker. Verifies every cited URL and flags fabricated sources. |
| **Audience** | Engaged observer. Submits clarifying questions mid-debate; gives a final opinion at close. |
| **Assessor** | Post-debate reviewer. Evaluates each agent's performance and produces an improvement report. |

The Chair is the lead Claude Code session. It spawns the other six agents as teammates, then
coordinates a structured debate through opening statements, multiple rebuttal rounds, and closing
statements before declaring a winner.

All debate entries are written to `shared/debate-log.jsonl` — an append-only log that acts as the
shared source of truth for all agents.

---

## Prerequisites

- **Claude Code** installed and authenticated
- **Agent Teams** experimental feature enabled (set the env var below)
- `bash`, `python3`, and `flock` available (standard on macOS and Linux)

---

## Running a Debate

### Step 1 — Choose a topic (optional)

Edit `config/debate-config.json` and set the `topic` field:

```json
{
  "topic": "Should artificial intelligence be used to make judicial sentencing decisions?",
  ...
}
```

If you leave `topic` empty, the Chair will use `topic_prompt` as the default topic, or ask you
for one at startup.

### Step 2 — Adjust round settings (optional)

```json
{
  "min_rounds": 3,
  "max_rounds": 8,
  "time_budget_minutes": 30
}
```

For a quick test run, set `"max_rounds": 1`.

### Step 3 — Start the debate

From the project directory, launch Claude Code with Agent Teams enabled:

```bash
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions
```

Once the Claude Code prompt appears, **type the following to begin**:

```
Start the debate.
```

That's all you need to say. The Chair reads `CLAUDE.md` automatically when Claude Code starts,
so it already knows its role. Sending "Start the debate." triggers the startup sequence:

1. Read the config and confirm (or ask for) the topic
2. Create a timestamped output directory under `output/`
3. Initialise `shared/debate-log.jsonl`
4. Spawn the Promoter, Detractor, Reporter, Verifier, Audience, and Assessor agents
5. Run the debate through all phases automatically

> **Tip:** If you want to use a specific topic rather than the one in config, you can say:
> `Start the debate. The topic is: [your topic here].`

### Step 4 — Watch the debate

The Chair narrates progress in its main session. If you have `tmux` available, you can split each
agent into its own pane for full visibility:

```bash
tmux new-session -s debate
export CLAUDE_CODE_SPAWN_BACKEND=tmux
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions
```

You can also tail the shared log in another terminal:

```bash
tail -f shared/debate-log.jsonl | python3 -c "
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

`config/debate-config.json`:

| Field | Default | Description |
|---|---|---|
| `topic` | `""` | The debate proposition. Leave empty to use `topic_prompt`. |
| `topic_prompt` | _(example)_ | Fallback topic if `topic` is empty. |
| `min_rounds` | `3` | Minimum rebuttal rounds before the Chair may end the debate. |
| `max_rounds` | `8` | Hard cap on rebuttal rounds. |
| `time_budget_minutes` | `30` | Soft time limit. Chair may conclude early if exceeded. |
| `output_dir` | `""` | Set automatically at runtime — do not edit manually. |
| `models.chair` | `claude-opus-4-6` | Model for the Chair agent. |
| `models.promoter` | `claude-sonnet-4-6` | Model for the Promoter agent. |
| `models.detractor` | `claude-sonnet-4-6` | Model for the Detractor agent. |
| `models.reporter` | `claude-sonnet-4-6` | Model for the Reporter agent. |
| `models.verifier` | `claude-sonnet-4-6` | Model for the Verifier agent. |
| `models.audience` | `claude-sonnet-4-6` | Model for the Audience agent. |
| `models.assessor` | `claude-sonnet-4-6` | Model for the Assessor agent. |

---

## Debate Rules (Summary)

- All factual claims **must** cite a real, accessible URL. Fabricated URLs result in immediate
  disqualification of that argument.
- Speculative arguments must be explicitly labelled `[CONJECTURE]`.
- The Verifier independently checks cited sources using `WebFetch` and reports any fabrications
  to the Chair urgently.
- The Chair's rulings are final. Redacted entries are struck from the record; the Reporter
  replaces them with `[REDACTED — reason]` markers.
- The Reporter never takes sides. The blog post is suppressed entirely if the debate is declared
  void.

See `CLAUDE.md` for the complete set of 20 rules.

---

## Project Structure

```
ai-debate/
├── CLAUDE.md                   # Chair instructions + shared rules (read by ALL agents)
├── README.md                   # This file
├── config/
│   └── debate-config.json      # Runtime configuration
├── prompts/
│   ├── promoter.md             # Promoter agent system prompt
│   ├── detractor.md            # Detractor agent system prompt
│   ├── reporter.md             # Reporter agent system prompt
│   ├── verifier.md             # Verifier agent system prompt
│   ├── audience.md             # Audience agent system prompt
│   └── assessor.md             # Assessor agent system prompt
├── shared/
│   ├── debate-log.jsonl        # Append-only debate log (reset before each run)
│   └── write-log.sh            # Atomic JSONL writer (used by all agents)
└── output/                     # One subdirectory created per debate run
```

---

## Resetting Between Runs

The debate log accumulates across runs unless cleared. Before starting a fresh debate:

```bash
> shared/debate-log.jsonl
```

The Chair also does this automatically during its startup sequence.

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
