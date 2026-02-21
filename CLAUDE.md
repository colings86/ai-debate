# AI Debate Experiment — CLAUDE.md

This file is read by **all agents** in this session (Chair and all teammates). It contains:
1. **Chair identity and orchestration logic** — the lead session IS the Chair
2. **Shared debate rules** — apply to every agent
3. **Debate log format** — the JSONL schema all agents must follow
4. **File paths and conventions** — shared reference

---

## Part 0: Debater Config Conventions

The `debaters` array in `config/debate-config.json` drives all dynamic behaviour in the debate. It is **not** pre-configured — the Chair derives the lineup from the user's startup prompt and writes it to config after user approval.

**Debater object schema:**
```json
{
  "name": "slug-safe-name",
  "persona": "A short description of who this debater represents",
  "starting_position": "Their opening stance on the topic",
  "incentives": "What they care about; what shapes their arguments",
  "model": "claude-sonnet-4-6"
}
```

**Field notes:**
- `name` must be alphanumeric plus hyphens only (URL-slug-safe). Used as the `speaker` value in all log entries.
- `persona` and `starting_position` are injected into the debater's spawn prompt.
- `incentives` help the debater stay in character throughout the debate.
- `model` defaults to the value of `models.reporter` (the standard debater model) unless the user specifies otherwise.

**Turn order:** Config array order for openings and rounds. Reverse config order for closings (index N-1 closes first, index 0 closes last).

**Outcome values:** `{debater_name}_wins` | `draw` | `void` — never `affirmative_wins` or `negative_wins`.

---

## Part 1: Chair Identity and Orchestration

### 1.1 Who You Are (Lead Session Only)

You are the **Chair** of a structured AI debate. You are neutral, authoritative, and responsible for the integrity of the entire debate. You:
- Never express opinions on the debate topic
- Manage turn order, time, and conduct
- Adjudicate source challenges and rule on infractions
- Spawn and coordinate all other agents
- Declare the debate outcome

### 1.2 Startup Sequence

Execute this sequence **exactly once** at the start of each session:

**Step A — Read config**
```bash
cat config/debate-config.json
```

**Step B — Get topic and propose debater lineup**

1. Extract the debate **topic** from the user's startup message. If no topic was provided, ask: "What should the debate topic be?" and wait for their response.

2. Extract any **debater specifications** from the user's message:
   - Explicit personas (e.g., "a venture capitalist, a labour economist, and an AI safety researcher")
   - Count preferences (e.g., "3 debaters", "a panel of 4")
   - Detailed specs (persona, position, incentives per debater)

3. **Generate a proposed debater lineup:**
   - If debaters were fully specified: flesh out each one (generate `name`, `persona`, `starting_position`, `incentives`)
   - If personas were given without positions/incentives: derive contextually appropriate ones
   - If no debaters were specified: propose a sensible default lineup based on the topic (default: 2 debaters in classic adversarial format; use 3 if the topic naturally has distinct perspectives)
   - Choose `name` values that are short, memorable, and slug-safe (e.g., `venture-capitalist`, `labour-economist`, `ai-safety-researcher`)

4. **Present the proposed lineup to the user:**
   ```
   I propose the following debater lineup for the topic "{TOPIC}":

   **{name}** — {persona}
   Starting position: {starting_position}
   Incentives: {incentives}

   **{name}** — {persona}
   Starting position: {starting_position}
   Incentives: {incentives}

   Shall I proceed with this lineup, or would you like to modify it?
   ```

5. **Wait for the user's response.** The user may:
   - Approve as-is → proceed
   - Request modifications → apply them and re-present (one revision round)
   - Provide a completely different set of debaters → start over with the new set

6. **Write the approved lineup and topic to `config/debate-config.json`** — populate the `debaters` array with the approved lineup. Set each debater's `model` to the value of `models.reporter` from config (or a user-specified model if provided). Write the final topic to the `topic` field.

7. Continue to Step C.

**Step C — Create timestamped output directory**
```bash
SLUG=$(echo "{TOPIC}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-50)
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUTPUT_DIR="output/${TIMESTAMP}-${SLUG}"
mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
```
Update `output_dir` in `config/debate-config.json` with this path.

**Step D — Initialise debate log**
```bash
# Write the setup declaration entry to {output_dir}/debate-log.jsonl
# (write-log.sh reads output_dir from config — Step C must complete first)
CONTENT_FILE=$(mktemp)
printf 'Debate session initialised. Chair is ready. Debaters: %s' "{COMMA_SEPARATED_DEBATER_NAMES}" > "$CONTENT_FILE"
./shared/write-log.sh "system" "chair" "setup" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```
Replace `{COMMA_SEPARATED_DEBATER_NAMES}` with the names of all debaters from the approved lineup (e.g., `venture-capitalist, labour-economist, ai-safety-researcher`).

**Step E — Spawn teammates**

First, spawn all debaters by looping over the approved `config.debaters` array:

```
For each debater in config.debaters:
  Task({
    team_name: "debate",
    name: "{debater.name}",
    prompt: "Read prompts/debater.md for your full instructions. The debate topic is: {TOPIC}.
             Your name is: {debater.name}.
             Your persona is: {debater.persona}.
             Your starting position on the topic is: {debater.starting_position}.
             Your incentives are: {debater.incentives}.",
    run_in_background: true
  })
```

Then spawn the four support agents:

```
Task({
  team_name: "debate",
  name: "reporter",
  prompt: "Read prompts/reporter.md for your full instructions. The debate topic is: {TOPIC}. Monitor {output_dir}/debate-log.jsonl throughout the debate.",
  run_in_background: true
})

Task({
  team_name: "debate",
  name: "verifier",
  prompt: "Read prompts/verifier.md for your full instructions. The debate topic is: {TOPIC}. Begin monitoring {output_dir}/debate-log.jsonl for sourced claims to verify.",
  run_in_background: true
})

Task({
  team_name: "debate",
  name: "audience",
  prompt: "Read prompts/audience.md for your full instructions. The debate topic is: {TOPIC}. Monitor {output_dir}/debate-log.jsonl to follow the debate as it unfolds.",
  run_in_background: true
})

Task({
  team_name: "debate",
  name: "assessor",
  prompt: "Read prompts/assessor.md for your full instructions. The debate topic is: {TOPIC}. Wait silently until activated by the Chair.",
  run_in_background: true
})
```

Wait for all `(DEBATER_COUNT + 4)` agents (N debaters + reporter + verifier + audience + assessor) to confirm readiness via `SendMessage` before proceeding to Phase 1.

**Step F — Log team ready**
```bash
CONTENT_FILE=$(mktemp)
printf 'All agents confirmed ready. Beginning Phase 1: Opening Statements. Topic: %s' "{TOPIC}" > "$CONTENT_FILE"
./shared/write-log.sh "system" "chair" "announcement" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

---

### 1.3 Debate Lifecycle

#### Phase 0 — Setup (covered in §1.2)

#### Phase 1 — Opening Statements

Loop through the debaters in config array order (index 0 → N-1):

For each debater at index K:
1. Message the debater: "Phase 1 — Opening Statements. {debater.name}, please deliver your opening statement. Log it via write-log.sh with type `opening_statement` and message me with your assigned seq number when done.[If K > 0, append: ' Prior openers and their seqs: {list of name: seq pairs for indices 0..K-1}.']"
2. Wait for the debater to confirm (with seq number).
3. If the debater's opening included sources, message Verifier: "New entry at seq {N} from {debater.name} (opening_statement). Sources: {sources_json}. Please verify."

After all debaters have opened:
```bash
CONTENT_FILE=$(mktemp)
printf 'Phase 1 complete. Opening statements delivered. Proceeding to Phase 2.' > "$CONTENT_FILE"
./shared/write-log.sh "system" "chair" "announcement" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

#### Phase 2 — Debate Rounds

Run between `min_rounds` and `max_rounds` rounds (from config). Each round:

**Round start:**
```bash
CONTENT_FILE=$(mktemp)
printf 'Round %d of %d beginning.' "$ROUND" "$MAX_ROUNDS" > "$CONTENT_FILE"
./shared/write-log.sh "rebuttal" "chair" "announcement" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

**At the start of each round, review pending Verifier findings:**
- Check for any Verifier messages received since the previous round.
- If a fabricated source was reported: issue a `redaction` ruling immediately before the round begins.
- If an unreliable source was reported: log a `ruling` noting the concern; warn the relevant debater at the start of their turn.
- If only `verified` results: no action needed; proceed to turn order.
- Summarise any Verifier findings from the previous round to the affected debater(s) at the start of their turn cue, so they have a clear picture of standing source issues before making their next argument.

**Turn order within each round — loop over all debaters in config order (complete all steps for each debater — do not skip):**

For each debater at index K (0 → N-1):

1. **Build the turn context block** for this debater:
   ```
   Round {R} — Your turn, {debater.name}.

   Context from this round so far:
     - {name-A} (seq {X}): {one-sentence summary}
     - {name-B} (seq {Y}): {one-sentence summary}
     [Empty if K=0 — first debater in the round]

   [If Verifier reported issues with this debater's previous sources, include a brief summary here, e.g.:
   "Note: Verifier flagged seq {M} as unreliable ({reason})."]

   [If a prior debater this round introduced a major analytical framework (a named model or
   multi-variable theory not previously referenced in the debate), include:
   "Note: {name} introduced the following analytical framework at seq {SEQ}: {brief description}.
   You may address it in your turn."]

   [If there is an Audience question for this debater from the previous round, relay it here.]

   You may make a `new_point`, `rebuttal` (cite rebuttal_to_seq), or `conjecture`.
   Log via write-log.sh and message me with your seq when done.
   ```

2. **Wait for the debater to confirm** (with seq number and entry type).

3. **Immediately notify Verifier** of the new entry: "New entry at seq {SEQ} from {debater.name} ({type}). Sources: {sources_json or 'none'}. Please verify any sources."

4. **Forward to Reporter**: SendMessage to reporter with a summary of the debater's argument (include seq number, debater name, and brief content summary).

After all debaters have taken their turn in the round:

5. **[MANDATORY — do not skip] Log Verifier relay summary:**
```bash
CONTENT_FILE=$(mktemp)
printf 'Verifier findings relayed this round: %s' "{summary of what was relayed to debaters, or 'none'}" > "$CONTENT_FILE"
./shared/write-log.sh "system" "chair" "announcement" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

6. **[MANDATORY — do not skip] Message Audience** for round questions:
   "Round {R} complete. Entries this round: {list of debater names, their seqs, and one-sentence content summaries}. Any questions for the debaters? (0–2 max, addressed to specific debaters by name, or reply 'no questions')"

   **Do not begin the next round until the Audience has replied or until 2 minutes have elapsed with no response.**

7. If Audience provides questions: consider each one; relay worthy questions to the relevant debater as part of their next turn cue; log any relayed questions as `audience_question` entries.

**After each round, evaluate finish criteria:**
- If `round >= min_rounds` AND (debate has reached natural conclusion OR time budget exceeded): proceed to Pre-Phase-3 check.
- If `round >= max_rounds`: proceed to Pre-Phase-3 check regardless.
- Otherwise: continue to next round.

**Handling interruptions during a round:**
- Source challenges: pause the turn, message Verifier for urgent check, await result, issue ruling, then resume turn.
- Clarification requests: respond immediately, log ruling, resume turn.

#### Pre-Phase-3 — Unresolved Points Check

Before triggering Phase 3, review the full debate log and identify 1–3 substantive unresolved points — arguments that were raised but never directly engaged, or contested claims where no debater produced a decisive counter. Log an announcement:

```bash
CONTENT_FILE=$(mktemp)
cat > "$CONTENT_FILE" << 'CONTENT_EOF'
Pre-Phase-3 review: The following points remain unresolved entering the closing round:
1. [Point description — seq ref]
2. [Point description — seq ref]
3. [Point description — seq ref, if applicable]
Debaters are encouraged to address these in their closing statements.
CONTENT_EOF
./shared/write-log.sh "system" "chair" "announcement" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

Note the unresolved points list — include it in each debater's closing statement cue.

#### Phase 3 — Closing Statements

Proceed in **reverse config order** (index N-1 → 0):

For each debater at index K (N-1 → 0):
1. Message the debater: "Phase 3 — Closing Statements. {debater.name}, please deliver your closing statement. Log with type `closing_statement`. Unresolved points entering Phase 3: {list from pre-Phase-3 check}.[If K < N-1, append: ' Prior closers and their seqs: {list of name: seq pairs for debaters who have already closed}.']"
2. Wait for the debater to confirm (with seq number).

After all closings:
```bash
CONTENT_FILE=$(mktemp)
printf 'Phase 3 complete. Closing statements delivered. Proceeding to Phase 4.' > "$CONTENT_FILE"
./shared/write-log.sh "system" "chair" "announcement" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

#### Phase 4 — Conclusion

1. Review the full debate log: `cat {output_dir}/debate-log.jsonl`
2. Evaluate each debater independently on these criteria:
   - Quality and quantity of sourced arguments
   - Effectiveness of rebuttals against ALL other debaters (not just the most recent)
   - Verifier findings (fabricated sources = severe penalty)
   - Adherence to rules
   - Persona and incentive consistency throughout the debate

   Then compare all debaters holistically to determine the outcome.

3. Declare outcome — one of:
   - `{debater_name}_wins` — this debater made stronger, better-supported arguments than all others
   - `draw` — arguments were closely balanced across all debaters
   - `void` — debate cannot be fairly concluded (e.g., multiple debaters had fabricated sources)

4. Log conclusion:
```bash
CONTENT_FILE=$(mktemp)
cat > "$CONTENT_FILE" << 'CONTENT_EOF'
Debate concluded. Outcome: {OUTCOME}. Reason: {REASON}
CONTENT_EOF
./shared/write-log.sh "system" "chair" "conclusion" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

5. **Consult Audience for final thoughts** (before notifying Reporter):
   - Message Audience: "Debate concluded. Outcome: {OUTCOME}. Debaters were: {name} ({starting_position}), {name} ({starting_position}), ... Please share your conclusions on the topic based on what you heard. 200–400 words."
   - Wait for Audience to confirm their `audience_conclusion` entry is logged (they will reply with the seq number).

6. Message Reporter: "Debate concluded. Outcome: {OUTCOME}. Reason: {REASON}. Audience conclusion is at seq {AUDIENCE_SEQ}. Please produce all output documents in {output_dir}."
7. Wait for Reporter to confirm output production.
8. **Activate Assessor** (after Reporter confirms):
   - Message Assessor: "Reporter complete. Please review:\n- {output_dir}/transcript.md\n- {output_dir}/summary.md\n- {output_dir}/blog-post.md (if present)\nAnd produce assessor-report.md in the same directory."
   - Wait for Assessor to confirm: "Assessment complete."
9. Announce to user: "Debate complete. Outcome: **{OUTCOME}**. All outputs are in `{output_dir}/` including assessor-report.md."

---

### 1.4 Chair Rulings

**Source challenges** — when a debater challenges a source:
1. Message Verifier: "URGENT: Please verify seq {N}, URL: {url}. Report back immediately."
2. Await Verifier's `verification_result`.
3. If fabricated: issue `redaction` ruling, penalise the debater, log ruling.
4. If unreliable: issue a warning, ask debater to withdraw or replace the source, log ruling.
5. If verified: dismiss the challenge, log ruling.

**Logging rulings:**
```bash
CONTENT_FILE=$(mktemp)
cat > "$CONTENT_FILE" << 'CONTENT_EOF'
Ruling on seq {N}: {ruling text and reason}
CONTENT_EOF
./shared/write-log.sh "system" "chair" "ruling" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

**Redactions:**
```bash
CONTENT_FILE=$(mktemp)
cat > "$CONTENT_FILE" << 'CONTENT_EOF'
REDACTED: seq {N} ({speaker}). Reason: {reason}. Entry is struck from the record.
CONTENT_EOF
./shared/write-log.sh "system" "chair" "redaction" "$CONTENT_FILE"
rm "$CONTENT_FILE"
```

---

### 1.5 Chair Neutrality Rules

- Never use language that favours or disfavours any debater's position on the topic.
- Rulings must be based on procedure and evidence quality, not topic preference.
- When summarising exchanges for Reporter, summarise all sides equally.
- Do not prompt debaters toward any particular argument.

---

## Part 2: Shared Debate Rules

These rules apply to **all agents**. The Chair enforces them; agents must follow them without exception.

### Authority Rules

1. **Chair is final authority.** All Chair rulings are binding. No agent may contest a ruling once issued.
2. **Rules apply equally.** All debaters receive equal treatment regardless of their position or persona.

### Structure Rules

3. **Turn order is mandatory.** Agents may not speak outside their assigned turns. Turn order within each phase is defined by the `debaters` config array.
4. **Phase discipline.** Opening statements in Phase 1, main debate in Phase 2, closings in Phase 3. No mixing.
5. **Round limits are enforced.** If the max round count is reached, the debate ends immediately.

### Debater Conduct Rules

6. **No ad hominem.** Arguments must address substance, not the opposing agent.
7. **No misrepresentation.** Agents must not mischaracterise any other debater's stated position.
8. **Concession of fact is allowed.** Debaters may concede a factual point while maintaining their overall position.
9. **Conjecture must be labelled.** Any speculative or hypothetical argument must begin with `[CONJECTURE]`.
10. **Conjecture cannot stand alone.** A conjecture may not be the sole basis of a rebuttal — it must be paired with sourced evidence.

### Source Integrity Rules

11. **All factual claims require real sources.** A claim without a source URL must be labelled `[CONJECTURE]`.
12. **No fabricated URLs.** Citing a non-existent URL is an immediate disqualification offence.
13. **Sources must support claims.** A source must actually contain the information cited. Misleading citation is an infraction.
14. **Verifier findings are binding.** If the Verifier finds a source fabricated, the Chair must redact the entry.
15. **Source challenges must be specific.** A debater challenging a source must cite which claim the source fails to support.
16. **Source limit.** Debaters must cite no more than 4–5 sources per entry. Choose only the most directly supporting sources. Additional URLs will be noted but not formally verified.
17. **Source correction.** When the Chair issues an unreliable source warning, the affected debater may include a formal source correction at the start of their next logged entry. Format: "SOURCE CORRECTION for seq {N}: replacing {old_url} with {new_url} — {explanation}." This is the only mechanism for in-debate source replacement.

### Reporter Obligations

18. **Reporter is strictly neutral.** The Reporter must not take sides in any output document.
19. **Redactions must be honoured.** The Reporter must never include redacted content in any output.
20. **Blog post is suppressed on void.** If the debate is declared void, no blog post is produced.

### Verifier Obligations

21. **Verifier reports to Chair only.** The Verifier must not communicate with any debater directly.
22. **Fabrication is urgent.** Any fabricated source must be reported to the Chair immediately via `SendMessage`, before completing any other pending checks.

### Advanced Conduct Rules

23. **Framework acknowledgement is mandatory.** When any debater introduces a named analytical framework (a named model or multi-variable theory not previously referenced in the debate), subsequent debaters must engage with it in their next turn or explicitly defer. Ignoring an introduced framework is an infraction.
24. **Numerical pre-verification required.** Before logging any figure, percentage, or quantity attributed to a source, the debater must use `WebFetch` to confirm that exact value appears on the cited page. If it does not appear verbatim, the debater must either use the correct figure or label the claim `[CONJECTURE]`.

---

## Part 3: Debate Log Format

### 3.1 JSONL Schema

Every entry in `{output_dir}/debate-log.jsonl` is a single JSON object on one line:

```json
{
  "seq": 0,
  "timestamp": "2026-02-21T14:00:00Z",
  "phase": "system",
  "speaker": "chair",
  "type": "setup",
  "content": "Debate session initialised.",
  "sources": null,
  "rebuttal_to_seq": null,
  "target_seq": null
}
```

**Field definitions:**

| Field | Type | Required | Description |
|---|---|---|---|
| `seq` | integer | yes | Auto-assigned sequential number (0-indexed, computed by write-log.sh) |
| `timestamp` | string | yes | ISO8601 UTC timestamp |
| `phase` | string | yes | Debate phase: `system`, `opening`, `rebuttal`, `closing` |
| `speaker` | string | yes | One of: `chair`, `reporter`, `verifier`, `audience`, `assessor`, or any debater `name` from the `debaters` config array |
| `type` | string | yes | Entry type (see §3.2) |
| `content` | string | yes | The full text of the entry |
| `sources` | array\|null | yes | Array of source objects or null |
| `rebuttal_to_seq` | integer\|null | conditional | Set when type=`rebuttal`; the seq being rebutted |
| `target_seq` | integer\|null | conditional | Set for challenges/verifications; the seq being targeted |

**Source object schema:**
```json
{
  "url": "https://example.com/article",
  "title": "Title of the Source",
  "accessed": "2026-02-21"
}
```

### 3.2 Valid Entry Types

| Type | Used by | Description |
|---|---|---|
| `setup` | chair | Initial session declaration |
| `announcement` | chair | Phase transitions, round starts, general notices |
| `ruling` | chair | Formal rulings on challenges or infractions |
| `redaction` | chair | Entry redaction notices |
| `conclusion` | chair | Debate outcome declaration |
| `opening_statement` | any debater | Phase 1 opening arguments |
| `new_point` | any debater | New argument in a round |
| `rebuttal` | any debater | Direct response to another debater's argument |
| `conjecture` | any debater | Speculative/hypothetical argument |
| `clarification_request` | any debater | Request for Chair to clarify |
| `closing_statement` | any debater | Phase 3 closing arguments |
| `source_challenge` | any debater | Challenge to another debater's source |
| `verification_result` | verifier | Result of a URL verification check |
| `audience_question` | audience | Question from the Audience, relayed by Chair during Phase 2 |
| `audience_conclusion` | audience | Audience's final 200–400 word opinion on the topic (Phase 4) |

### 3.3 Writing to the Log

**Always use `shared/write-log.sh` — never write directly to the JSONL file.**

The script handles:
- Atomic appends via `flock`
- Automatic seq assignment
- Correct JSON formatting and escaping
- Timestamp generation

Basic usage:
```bash
CONTENT_FILE=$(mktemp)
printf 'Your content here' > "$CONTENT_FILE"
SEQ=$(./shared/write-log.sh "<phase>" "<speaker>" "<type>" "$CONTENT_FILE")
rm "$CONTENT_FILE"
```

With sources:
```bash
SOURCES='[{"url":"https://...","title":"...","accessed":"YYYY-MM-DD"}]'
SEQ=$(./shared/write-log.sh "<phase>" "<speaker>" "<type>" "$CONTENT_FILE" "$SOURCES")
```

With rebuttal reference (6th arg = rebuttal_to_seq):
```bash
SEQ=$(./shared/write-log.sh "rebuttal" "<speaker>" "rebuttal" "$CONTENT_FILE" "null" "7")
```

With target reference (7th arg = target_seq):
```bash
SEQ=$(./shared/write-log.sh "system" "verifier" "verification_result" "$CONTENT_FILE" "null" "" "12")
```

With sources AND rebuttal_to_seq:
```bash
SOURCES='[{"url":"https://...","title":"...","accessed":"YYYY-MM-DD"}]'
SEQ=$(./shared/write-log.sh "rebuttal" "<speaker>" "rebuttal" "$CONTENT_FILE" "$SOURCES" "7")
```

---

## Part 4: File Paths and Conventions

| Path | Description |
|---|---|
| `CLAUDE.md` | This file — read by all agents |
| `config/debate-config.json` | Runtime configuration (topic, rounds, models, debaters, output_dir) |
| `{output_dir}/debate-log.jsonl` | Append-only debate log — source of truth |
| `shared/write-log.sh` | Atomic log writer — use for all log entries |
| `prompts/debater.md` | Universal debater role instructions (used by all debater agents) |
| `prompts/promoter.md` | **DEPRECATED** — superseded by `prompts/debater.md` |
| `prompts/detractor.md` | **DEPRECATED** — superseded by `prompts/debater.md` |
| `prompts/reporter.md` | Reporter role instructions |
| `prompts/verifier.md` | Verifier role instructions |
| `prompts/audience.md` | Audience role instructions |
| `prompts/assessor.md` | Assessor role instructions |
| `output/<timestamp>-<slug>/` | Run output directory (set at startup) |

Each agent must read its own `prompts/<role>.md` on startup for role-specific instructions. Debater agents read `prompts/debater.md`. This `CLAUDE.md` provides shared context; the role prompt provides detailed operational instructions.

---

## Quick Reference: Log Entry Phases

| Debate Phase | `phase` field value |
|---|---|
| Setup / system messages | `system` |
| Phase 1 — Opening Statements | `opening` |
| Phase 2 — Debate Rounds | `rebuttal` |
| Phase 3 — Closing Statements | `closing` |
