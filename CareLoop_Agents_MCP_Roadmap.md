# CareLoop — AI Agents & MCP Connector Roadmap

**Companion to:** `CareLoop_Master_PRD.md` (Section 13 summarizes this document; this is the full build-planning detail).
**Purpose:** Inventory every AI agent and MCP connector applicable to CareLoop, in build-priority order, with complexity, dependencies, and the specific guardrail each one inherits from the main PRD. Read the main PRD first — this document assumes Sections 4 (parsing), 7 (doctor console consent flow), 9 (payer access), and 11 (access control) as given context and doesn't repeat their detail.

**The one rule that governs every entry in this document:** an agent drafts, summarizes, flags, or prepares. A human — the member, the doctor, or the payer's underwriter — confirms and acts. No agent below makes an autonomous clinical or underwriting decision, edits the canonical dictionary unsupervised, or bypasses a consent gate. Where an entry's design invites a shortcut around that rule, this document says so explicitly rather than leaving it implicit.

---

## 1. How to read the priority tiers

- **Tier 1 — build early, low risk.** Sits directly on top of already-specified deterministic pipelines (parsing, trend data). Doesn't touch consent gates or clinical judgment calls.
- **Tier 2 — build once the doctor console is stable.** Depends on Section 7's check-in/consent/unlock flow already working correctly.
- **Tier 3 — build last, highest scrutiny.** Touches payer access or dictionary governance — the two areas the main PRD already flags as highest-risk (Section 11 preamble, Section 5.3).
- **Deferred / stub only.** Explicitly out of scope for the current build (mirrors Master PRD Section 14).

---

## 2. Agent Inventory

### 2.1 Document intake agent — Tier 1

- **What it does:** This is the Section 4 parsing pipeline (classify → extract → match → validate → route), described as an agent because it's genuinely multi-step reasoning over unstructured input, not a single API call. No new capability beyond what Section 4 already specifies — listed here for completeness since it's the template every other agent in this document follows.
- **Depends on:** Section 4 pipeline, Section 5 dictionary.
- **Guardrail inherited:** Section 4.4/4.5 — Tier 2/3 matches always route to human review, never auto-accept.
- **Build note:** Already first in the build order (Master PRD Section 12.2, step 2). Nothing new to sequence here.

### 2.2 Health insights agent — Tier 1

- **What it does:** Reads a member's newly confirmed lab values against their own history and drafts a short, plain-language summary for the Health Analysis tab — e.g. "Your fasting glucose has been trending down for three checkups in a row, and is now back in range." Output is display text only; it does not write any structured field.
- **Depends on:** `ExtractedParameter` time series (Section 6), the Health Analysis tab already in the member app.
- **Guardrail:** Must not phrase output as a diagnosis or a recommendation to change treatment — describes what changed, not what to do about it. Any language suggesting a course of action should route the member to "discuss with your doctor," not give the advice itself.
- **Complexity:** Low-medium. The hard part is tone, not data access — getting a language model to describe a trend factually without drifting into clinical advice needs explicit prompt-level constraints and should be tested against edge cases (e.g. a genuinely alarming trend) before shipping, not just typical ones.

### 2.3 Family care-coordinator agent — Tier 1

- **What it does:** Proactively surfaces things a busy family coordinator would otherwise have to remember manually: a senior parent overdue for an annual checkup, a medication that's about to run out based on prescribed duration, a child's vaccination due-date. This is the agent most directly aimed at the original problem statement this whole product started from.
- **Depends on:** `Member` profiles across a `Family`, `Prescription` duration fields, a vaccination-record document type (already in scope per Section 3.4's document types).
- **Guardrail:** Purely reminder/surfacing logic against dates already in the data — no clinical inference. Low risk by design; keep it that way rather than letting it grow into a health-advice feature over time.
- **Complexity:** Low. Mostly date-math and notification delivery once the underlying data exists.

### 2.4 Symptom intake agent — Tier 1

- **What it does:** Sits in front of the Symptoms & Observations tab and asks clarifying questions to help a member turn "I don't feel well" into a structured, dated entry — onset, severity, associated factors — without ever suggesting what might be causing it.
- **Depends on:** The Symptoms & Observations tab (already built in the member app prototype).
- **Guardrail:** This is the single agent in this document with the most direct self-harm/health-anxiety adjacent risk if built carelessly — it must never offer a diagnosis, a likelihood estimate, or a "you should worry about X" framing, only structure what the member already said. If a member describes something urgent (chest pain, breathing difficulty), the agent's job is to say so plainly and prompt them toward emergency care or their doctor, not to reason about it.
- **Complexity:** Medium — the conversational design needs real care here, more than the engineering.

### 2.5 Consent explainer agent — Tier 1 (ships alongside Tier 2 doctor-console work)

- **What it does:** Before a member taps Approve on a real-time consent request (Master PRD Section 7.1), explains in plain language exactly what's being requested — which doctor, for which visit, what scope of access. Specifically valuable for the OTP-fallback path used by senior parents, where an unassisted, legal-sounding consent screen is the actual usability barrier the BRD (Section 6, risk table) already flagged.
- **Depends on:** The `ConsentGrant` request object (Section 7.1), the OTP fallback flow.
- **Guardrail:** Explains, never nudges. Must present Approve and Deny with equal weight — this agent exists to inform the decision, not to increase approval rates. Track denial rates after this ships as a health check that it's staying neutral (same instinct as the BRD's Section 11 risk mitigation for consent-request wording).
- **Complexity:** Low-medium. Mostly a UI/copy problem with a language model doing the plain-language rewrite of structured request data.

### 2.6 Pre-visit prep agent — Tier 2

- **What it does:** The instant `consent_granted` fires (Section 7.1), summarizes the patient's flagged history into a one-screen brief for the doctor — the equivalent of the "Flagged since last visit" card already in the doctor console mockups, but agent-drafted rather than a fixed query, so it can prioritize what's actually relevant to the visit reason rather than just listing every out-of-range value.
- **Depends on:** Section 7.2's unlock event, `ExtractedParameter` and `Document` for the unlocked member only.
- **Guardrail:** Access scope is identical to what the doctor console already enforces (Section 7.2) — this agent has no broader read access than the human doctor does at that moment, and its output disappears when access is revoked on visit completion (Section 7.1), same as everything else in the unlocked session.
- **Complexity:** Medium. Needs the appointment's stated reason-for-visit (not currently a modeled field — add `Appointment.reason_for_visit` if this agent is prioritized) to prioritize relevantly rather than just summarizing everything.

### 2.7 Medication reconciliation agent — Tier 2

- **What it does:** While a doctor is drafting an e-prescription (Section 7.3), checks the draft against the patient's known allergies and current medications and flags a conflict before the doctor signs it — e.g. prescribing something in a drug family the patient is allergic to, or a duplicate/interacting medication already active.
- **Depends on:** `Allergy`, current `Prescription` records, a drug-interaction reference (external — likely needs its own data source/connector, not something to build from scratch).
- **Guardrail:** Flags for the doctor's attention; never blocks signing and never auto-edits the prescription. This is checking against structured facts already in the system (a known allergy, a known active medication), not making a clinical judgment call about whether a flagged conflict is actually a problem in this specific patient's case — that judgment stays with the doctor.
- **Complexity:** Medium-high. The reconciliation logic itself is straightforward; sourcing a reliable drug-interaction/allergy-class reference is the real work, and is a good candidate for an external MCP connector (a drug-database API) rather than an in-house dataset.

### 2.8 Risk-signal drafting agent — Tier 3

- **What it does:** Helps a `payer_analyst` interpret the population dashboard (Section 9) by drafting observations — e.g. "This plan tier's elevated-risk share has grown over the last two quarters" — as a starting point for a human underwriter's own analysis.
- **Depends on:** `RiskSignal` objects only (Section 9's population dashboard).
- **Guardrail — the strictest in this document:** reads `RiskSignal` exclusively, never `ExtractedParameter` or `Document` — the same signal-not-source boundary the main PRD already enforces for human payer users (Section 9) applies identically to this agent; giving an agent broader access "just for drafting purposes" would quietly reopen the exact data-minimization boundary Section 11 was built to close. Output is always framed as an observation for review, never a recommendation ("consider adjusting X") — that phrasing crosses into the underwriting-decision territory the BRD (BR-16) explicitly rules out.
- **Complexity:** Medium, but gate this behind real confidence in the access-control layer (Master PRD Section 12.2, step 5) — this is deliberately the last agent to build, not because it's technically hardest, but because it's the one where a scoping mistake has the most serious consequence.

### 2.9 Dictionary curation agent — Tier 3

- **What it does:** Two jobs: (a) periodically re-checks canonical reference ranges against current published sources and flags drift — automating the kind of verification pass done manually for dictionary v1.1.0 (Master PRD Section 5.4); (b) for every item in the `platform_admin` review queue (new-candidate or Tier-3 match, Section 4.4/5.3), pre-drafts a proposed resolution — "likely a new alias of `hematocrit`" — for the admin to accept or override.
- **Depends on:** `CanonicalParameter` (Section 5.1), the admin review queue.
- **Guardrail:** Proposes, never applies. Every dictionary change still requires `platform_admin` action — this agent's entire value is cutting review time, not removing the review step. Given Section 5.4's own finding that authoritative sources disagree with each other on reference ranges, an agent auto-applying a "corrected" range without human review would be actively dangerous, not just against policy.
- **Complexity:** Medium-high for the range-drift-checking half (needs reliable source access, ideally via a dedicated research/search connector); lower for the alias-resolution half (mostly the same three-tier matching logic already built for Section 4.4, applied to the admin's queue instead of a live upload).

---

## 3. MCP Connector Inventory

| Connector | Feeds | Priority | Notes |
|---|---|---|---|
| Calendar (Google/Outlook) | Appointment booking | Tier 1 | Straightforward push-only integration; no read access to the member's broader calendar needed. |
| Email | Document intake agent | Tier 1 | Watch for lab-report attachments from known diagnostic-lab sender domains; always require member confirmation before filing, same as any other upload (Section 3.3). |
| WhatsApp Business | Document intake agent | Tier 1 | High relevance for the India market this app targets — report-photo-by-WhatsApp is a common existing behavior, so this lowers the adoption barrier more than almost anything else on this list. |
| Maps/places | Appointment booking (provider search) | Tier 1 | Read-only location search. |
| Lab-chain APIs (Thyrocare, Dr Lal PathLabs, Metropolis, etc.) | Document intake agent | Tier 2 | Where a lab exposes structured results directly, this bypasses OCR/extraction entirely for that source — same trusted-source pattern as provider-issued e-prescriptions (Section 3.4). Worth prioritizing per-lab integration in proportion to how many golden-test-set reports come from that lab. |
| Drug-interaction/allergy-class database | Medication reconciliation agent | Tier 2 | External reference data, not something to build in-house — evaluate licensing/coverage for the Indian drug-naming conventions specifically, since most consumer drug-interaction APIs are US-market-first. |
| Reference-range research/search connector | Dictionary curation agent | Tier 3 | Whatever this app already uses for its own research capability is the natural fit — no new integration category, just a scheduled/agentic use of it. |
| Pharmacy partner APIs (1mg, PharmEasy, Apollo) | Future one-click ordering | Deferred | Explicitly Phase-4 per Master PRD Section 14 — stub the interface so `Prescription` data is ready, do not build the live connector yet. |
| ABDM/ABHA | Future national record exchange | Deferred | Explicitly future scope per Master PRD Section 14 — same treatment. |

---

## 4. Suggested Build Sequencing

This slots into the Master PRD's existing build order (Section 12.2) rather than replacing it:

1. Ship the deterministic core first (Master PRD Section 12.2, steps 1–4) — no agent in this document is useful before that foundation exists.
2. **Tier 1 agents** (2.2–2.5) and **Tier 1 connectors** (Calendar, Email, WhatsApp, Maps) can follow immediately after — they sit on top of the member app and don't depend on the doctor console being finished.
3. **Tier 2 agents** (2.6–2.7) and their connectors ship alongside or just after the doctor console (Master PRD Section 12.2, step 4) — they're meaningless before `consent_granted` exists as a real event.
4. **Tier 3 agents** (2.8–2.9) ship only after the payer module (Master PRD Section 12.2, step 5) is live and its access-control layer has the automated tests Section 12.4 already requires — do not accelerate these ahead of that layer being proven, regardless of how ready the agent logic itself feels.
5. Deferred connectors (pharmacy, ABDM) stay stubbed until their owning feature phase, per Master PRD Section 14.

---

## 5. What This Document Deliberately Does Not Do

- It does not propose an agent for anything touching diagnosis, treatment recommendation, or underwriting decisions — those stay human tasks throughout, by design, not by omission.
- It does not propose a "general health chatbot" as a standalone feature. Every agent above is scoped to one specific, bounded task inside an existing flow — a general open-ended medical-advice chat surface is a materially different (and materially riskier) product decision than anything specified here, and isn't something this document recommends building.
