# CareLoop — Master PRD for Claude Code

**Version:** 2.0 (consolidated, engineering-ready)
**Purpose of this specific document:** This is the single input document to hand to Claude Code to build CareLoop. It consolidates and supersedes the earlier platform PRD and the doctor-console BRD into one coherent spec, written so an AI coding agent with no other context can read it once and start building correctly. Where earlier documents are referenced, it's for traceability — you do not need to read them first; everything you need to build is repeated or expanded here.

**Companion file:** `CareLoop_Parameter_Dictionary.json`, in the same folder as this document, is the master canonical parameter dictionary (129 parameters across 18 categories, version 1.1.0 — cross-checked against web sources, not training data alone; see Section 5.4). Load it as seed/reference data — do not re-derive it from scratch. Section 5 explains its structure and how to use it.

**Second companion file:** `CareLoop_Agents_MCP_Roadmap.md` gives the full build-priority breakdown for the AI agents and MCP connectors summarized in Section 13.

---

## 0. Read this first — a note on the .apk request and how to use this document

The person requesting this build asked for the application "in .apk format." Be upfront about what that means in practice, in whatever environment you're running in:

- **If you (Claude Code) are running in a sandboxed environment with no Android SDK, no Gradle, and no network access to Google's Maven/Android repositories**, you cannot compile a real, installable `.apk` — that requires the Android SDK build-tools, a JDK, and typically a multi-hundred-megabyte toolchain download from Google's servers. Don't fabricate a fake or empty `.apk` file to satisfy the letter of the request — say plainly that this step needs an environment with Android build tooling, and produce everything else (a fully working, buildable project) so the person is one `./gradlew assembleDebug` (or equivalent) away from a real APK on their own machine or CI.
- **If you are running with real Android build tooling available** (Android Studio, a configured Gradle/Android SDK environment, or a CI runner with those installed), build the app per Section 12's recommended stack and produce the actual signed/debug APK as the final deliverable.
- **Recommended path to get to a real APK fastest, regardless of environment:** build CareLoop as a well-structured web app first (Sections 3–10 describe the product, not a specific framework), then package it as an installable Android app using **Capacitor** (wraps a web app in a thin native Android shell) rather than attempting a full native Kotlin/Java rewrite. This is dramatically faster to a working APK than native development, keeps one codebase for web + Android, and every screen described in this document (member app, doctor console) works the same way inside a Capacitor shell as it does in a browser. Section 12 gives the exact commands.
- If a real APK genuinely cannot be produced in your environment, say so explicitly in your final summary to the person, and hand back a project that builds cleanly with one documented command — don't let this limitation go unstated.

---

## 1. Product Summary

CareLoop is a three-sided platform:

1. **Members** — individuals and their families who store medical records and insurance policies, understand their health over time, and get care.
2. **Providers (doctors/clinics)** — who see a patient's history only after the patient checks in *and* freshly consents in real time for that specific visit, and who issue e-prescriptions.
3. **Payers (insurers)** — who, only with explicit per-member consent, see derived risk signals (never raw documents) to inform underwriting.

The hardest, most central technical problem, and the one this document goes deepest on, is: **a member uploads a photo or PDF of a lab report from any lab, in any format, and the system must correctly read every value and file it under the right variable — reliably, across labs it has never seen before.** Sections 4–6 are the detailed spec for this. It is grounded in two real, structurally different lab reports (a Tata 1mg CBC report and a PharmEasy/Docon/Thyrocare Hemogram + trends report) that were used to validate the design and seed the dictionary — treat those as the first two entries in your test set, not hypothetical examples.

---

## 2. Actors & Roles

| Role | Who | Primary goal |
|---|---|---|
| `member_primary` | Family coordinator / account owner | Manage records and care for the whole family from one place |
| `member_dependent` | Spouse, child, senior parent | Has their own record timeline |
| `provider_doctor` | An individual doctor | View consented patient history at the point of care, issue e-prescriptions |
| `provider_clinic_admin` | Clinic front desk/admin | Manage doctor roster, perform patient check-in |
| `payer_analyst` | Insurer underwriting/analytics staff | View consented, derived risk signals across a covered population |
| `platform_admin` | CareLoop internal ops | Manage the canonical dictionary, review low-confidence extractions |

A login resolves to exactly one role context at a time.

---

## 3. Family Health Record Management

This section specifies how a family's records are organised and maintained — the foundation everything else builds on.

### 3.1 The family/member data model

- One `Family` has one `primary member` (the account owner/coordinator) and any number of `dependent members` (spouse, children, parents — matching the reference household of self, spouse, 2 children, 2 senior parents).
- Every member — primary or dependent — has their **own independent record timeline**. Records are never merged across members; a father's creatinine trend and a mother's creatinine trend are two entirely separate time series, even though they share a canonical parameter.
- The primary member can view and manage every dependent's profile by default. A dependent (e.g. a spouse) MAY be given their own login and self-management rights — build the data model to support this from day one (a `Member.login_credentials_ref` that can be null for a coordinator-managed profile or populated for a self-managed one), even if v1 only ships coordinator-managed dependents.
- Each member profile carries: name, date of birth, sex, blood group, a structured allergy list (not just free text), and a structured chronic-conditions list.

### 3.2 What "maintaining" records means, concretely

For each member, the system maintains four kinds of longitudinal data, all derived from uploaded/issued documents:

1. **The document library** — every original file (photo/PDF) ever uploaded or issued (prescription, lab report, scan, discharge summary, vaccination record, insurance policy), stored as-is, forever, as the source of truth.
2. **The extracted parameter time series** — every individual lab value pulled out of those documents, normalised to a canonical parameter, with its date, so "HbA1c over the last 3 years" is a single queryable series regardless of which of 5 different labs produced each reading (Sections 4–6).
3. **The medication/prescription history** — every prescription, whether uploaded from a photo of a handwritten scrip or issued directly by a provider in-app (the latter skips OCR entirely — see 3.4).
4. **The summary card** — allergies, chronic conditions, current medications, and the most recent out-of-range flags, computed live from the above, not separately maintained. This is the one screen a member can show a new doctor in ten seconds, and it's what a provider sees by default before any deeper history is shared (Section 8).

### 3.3 Uploading old/historical records

A member can upload records at any time, not just going forward — this is explicitly a "bring your old paper history into the system" product, not just a forward-only journal. Practically:

- The upload flow does not require the member to specify which member profile a document belongs to in advance if it's ambiguous — the system should suggest a member based on any name/age printed on the document (both reference reports print the patient's full name and age/DOB clearly) but always show a confirmation step before filing it, since a family account can easily have multiple documents arrive in a short window (e.g. an annual health-checkup day for two parents).
- A single physical lab visit is very often a **multi-page PDF** (both reference reports are 2+ pages). The system must treat pages sharing the same Lab Visit ID / Barcode ID / Order ID (both sample reports print this consistently on every page) as one logical document, not one document per page. Extract this identifier from the page header/footer during the classify step and use it to group pages before running extraction once per logical document.
- Old records are frequently **out of chronological order relative to upload order** (a member might upload last year's report today, after already uploading this year's). Every parameter record is keyed by its **test date**, extracted from the document, never by upload date — trend graphs and YoY comparisons sort and compare by test date exclusively.

### 3.4 Two ways data enters the system, and why they're handled differently

- **Member-uploaded documents** (photo/PDF of a report from any source) go through the full parsing pipeline in Section 4 — OCR/vision extraction, canonical mapping, confidence scoring, human review gate.
- **Provider-issued e-prescriptions** (Section 8) are entered as structured data directly by the doctor in the console — there is no OCR step, because the source is already structured. These still get canonicalised against the same medicine/parameter dictionary for consistency, but skip extraction entirely and land as `confirmed` immediately, since they come from a verified in-app action, not an image.

---

## 4. The Parsing & Normalization Pipeline

This is the detailed spec Claude Code should implement literally. It is deliberately more specific than a typical PRD section because getting this wrong quietly corrupts every downstream feature (graphs, YoY comparisons, doctor console flags).

### 4.1 Why a template-per-lab-vendor approach will not work — the evidence

Two real reports used to validate this design already prove templates don't scale:

- **Column layout differs.** Report A: `Test Name | Result | Unit | Bio. Ref. Interval | Method`. Report B: `Test Name | Methodology | Value | Units | Bio. Ref. Interval` — same information, different order, different header words.
- **Naming differs for identical concepts**, with zero shared substring in some cases: `HCT` vs. `Hematocrit (PCV)`; `RBC` vs. `Total RBC`. A parser matching on exact text or simple substring containment fails on these.
- **Some content isn't tabular at all.** One reference report includes a "Health Trends" page style where each parameter is rendered as an infographic card — a labelled range bar, a "Currently X, Increased by Y" delta callout, and a small sparkline of past values — with no table structure whatsoever. A text-only OCR-plus-table-parser approach cannot read this; the numbers and their meaning are encoded graphically.
- **Some rows have no fixed reference range at all.** Two hematology indices (RDWI, Mentzer Index) print "*Refer Note below" and refer to conditional clinical interpretation rules instead of a simple normal range.
- **Real pages mix data with noise** — NABL/QR badges, disclaimer paragraphs, and in one case active promotional banners (medicine discount codes, app-download prompts) appear on the same physical pages as clinical values.

Build for this reality from day one. Do not build a "Lab X parser" and a "Lab Y parser" as separate code paths.

### 4.2 Pipeline stages

```
1. INTAKE          → image/PDF received, stored in blob storage, checksum + Document record created
2. GROUP PAGES      → identify shared Lab Visit ID / Barcode ID / Order ID across pages of a multi-page upload;
                       treat as one logical document. Tag each page/region as DATA or NOISE (badges, ads,
                       disclaimers, signature blocks) — only DATA regions proceed to extraction.
3. CLASSIFY         → document type: prescription | lab_report | radiology_scan | discharge_summary |
                       vaccination_record | insurance_policy | other. A lab_report is further tagged by its
                       presentation: tabular | chart_infographic | narrative_handwritten — this tag doesn't
                       change the extraction model used (still vision-capable, see 4.3) but affects how you
                       validate output in testing.
4. EXTRACT          → a vision-capable model reads the actual rendered page (not a pre-OCR'd text dump) and
                       produces candidate tuples: for lab reports, (label_as_printed, value, unit,
                       printed_reference_range_or_null, test_date, ordering_lab_name); for prescriptions,
                       (medicine_name, dosage, frequency, duration, diagnosis_text).
5. NORMALIZE        → map each candidate label to a canonical_parameter_id via the three-tier matching
                       strategy (Section 4.4).
6. UNIT CONVERT      → if the extracted unit differs from the canonical unit and a conversion rule exists in
                       the dictionary, convert; otherwise flag for review rather than guessing.
7. RANGE RESOLUTION → if the source document printed its own reference range, store and use THAT range for
                       this result's in/out-of-range flag. Only fall back to the dictionary's
                       typical_reference_range when the document printed none. Never silently overwrite a
                       printed range with the dictionary default (see 4.6 for why this matters).
8. CONFIDENCE SCORE → combine match-tier confidence (4.4) and extraction-quality confidence into one score
                       per field.
9. VALIDATE          → sanity-check the value against the dictionary's plausible_range_for_validation,
                       independent of which tier matched — this catches OCR/digit errors (e.g. "11.0"
                       misread as "110") regardless of how confidently the label was matched.
10. STORE            → write to the time-series parameter store with status auto_accepted or pending_review,
                       linked to the source document, the matched canonical_parameter_id, the raw
                       label-as-printed, the resolved reference range, and the dictionary version used.
11. GRAPH-READY      → once confirmed, the value is available to trend graphs and YoY comparison (Section 7).
```

### 4.3 Extraction: vision-capable model over the rendered page, not text-only OCR

Given 4.1's evidence (especially the chart-infographic page style), the extraction step (stage 4) must operate on the actual visual rendering of the page — as a person would read it — not on a pre-extracted text blob from a conventional OCR engine. Use a vision-capable large language model for this step. This handles all three presentation styles (tabular, chart/infographic, handwritten) with one code path instead of three.

Per-lab template/layout caching is a valid **optimisation** once a specific lab's format has been successfully parsed before (store a lightweight layout fingerprint → extraction-strategy hint), but the general vision-based pipeline must always be the fallback and must always run for any format not already cached — never make the cache a hard dependency.

### 4.4 Three-tier canonical matching

For each extracted label, attempt matches in order, stopping at the first tier that produces a confident result:

1. **Tier 1 — exact alias match.** Normalise both the extracted label and every alias in the dictionary (lowercase, strip punctuation/whitespace variation) and compare. `"HCT"` and `"Hematocrit (PCV)"` are both listed as aliases of `hematocrit` in the dictionary — both hit Tier 1. Confidence ≈ 0.95–0.97.
2. **Tier 2 — fuzzy/substring match.** One normalised string contains the other (e.g. `"Sr. Creatinine"` contains `"creatinine"`). Confidence ≈ 0.70–0.75. **Always route to human review regardless of numeric score** — substring overlap also produces false positives (e.g. don't let "Absolute Neutrophil Count" fuzzy-match against "Absolute Basophil Count" just because most words overlap; word-overlap scoring should weight distinguishing words, not just count shared tokens).
3. **Tier 3 — semantic/embedding match.** No shared substring, but a medical-domain text-embedding model scores the two labels as similar (this is what's needed for `"HCT"` vs. `"Hematocrit (PCV)"`, which share zero characters in common). **Always route to human review**, never auto-accept, regardless of score — semantic similarity is a weaker signal than a printed alias and the failure mode (confusing two different but related parameters) is exactly the kind of mistake that corrupts a health trend silently.
4. **No match at any tier** → route to `platform_admin` as a **new-candidate parameter** (Section 6.3), not silently discarded and not silently stored under a guessed parameter.

Every match, at every tier, still passes through the independent plausibility validation (pipeline stage 9) — matching tier and value plausibility are two separate checks catching two different failure modes (wrong parameter vs. wrong digit).

### 4.5 Confidence thresholds and the review queue

- Tier-1 matches with combined confidence ≥ 0.85 → `auto_accepted`, immediately usable in graphs.
- Everything else (Tier 2, Tier 3, sub-threshold Tier 1, failed plausibility check) → `pending_review`, excluded from trend graphs and YoY comparisons until a human confirms it, and shown to the member with a visibly different state ("needs review") wherever it would otherwise appear.
- The member reviewing their own upload (via a confirm/edit step shown right after extraction) is a valid confirmation path for member-visible data. Genuinely new/unmatched parameter candidates (no canonical match at all) additionally always go to the `platform_admin` review queue regardless of what the member does, since adding a new canonical parameter is a dictionary-governance action, not a per-member one.

### 4.6 Reference ranges are not always a simple [low, high] — build for this now

The dictionary's `range_type` field (see Section 5) has five values, and each needs different handling:

- `fixed_range` — the normal case: shade a band between low and high on the trend graph, flag values outside it.
- `open_upper_bound` — e.g. the HDL/LDL ratio prints a range like "0.41 – 9999.0", which really means "no clinically meaningful upper limit". Don't shade an upper band that implies 9999 is a real ceiling; only enforce/shade the lower bound.
- `open_lower_bound` — the mirror case: e.g. HDL cholesterol, where higher is protective and there is no real "too high" cutoff for the app's purposes — only flag below the lower bound (e.g. 40 mg/dL), never shade or flag an upper band.
- `interpretive_rule` — e.g. the Mentzer Index and RDWI have no flat normal range at all; the source lab's own footnote gives conditional logic ("MI > 13 suggests X, MI < 13 suggests Y"). **Do not auto-encode this interpretive logic from report text without explicit clinical sign-off** — store and display the raw value, do not compute or display any automated in-range/out-of-range flag for these until a reviewing clinician has approved specific threshold logic. This is a clinical-safety boundary, not just a data-modelling choice.
- `qualitative` — e.g. urine protein/glucose (often reported as "Nil"/"Trace"/"Present" rather than a number), or serology screens (HBsAg, HIV, VDRL — typically "Reactive"/"Non-Reactive"). Store as a text/enum value, never coerce to a number, and never plot on a numeric trend graph — show these as a status timeline instead (Section 7.3).

And independent of `range_type`: **whenever the source document itself prints a reference range for a result, store and use that printed range for that specific result's flagging — never silently override it with the dictionary default.** Reference ranges genuinely vary by lab, instrument, and method (both reference reports show slightly different ranges for the same parameter, e.g. PDW: 9–17 fL in one report, 9.6–15.2 fL in the other). The dictionary's `typical_reference_range` is a fallback for when a report omits a range, and a bound for plausibility validation — it is not the source of truth when the report provided its own.

### 4.7 Noise filtering

Both reference reports carry NABL/QR badges, signature blocks, multi-city footers, legal disclaimers, and (in one case) active promotional banners on the same pages as clinical data. Stage 2's page/region tagging must exclude these from reaching the extraction step — this avoids wasted extraction calls and prevents a phone number or a discount code from ever being misread as a lab value.

### 4.8 Golden test set

Maintain a permanent, growing set of real (not synthetic) source documents used to regression-test the pipeline. Seed it on day one with the two reference reports this design was built against. Every time the extraction model, the matching logic, or the dictionary changes, re-run the full set and confirm no previously-correct mapping regresses. Every new lab format encountered in production should be added to this set the first time it's seen, not treated as a one-off fix.

---

## 5. The Master Canonical Parameter Dictionary

`CareLoop_Parameter_Dictionary.json` (companion file) is the master seed dictionary. **Load it into the dictionary store at setup time; do not hand-recreate it from this document's prose.**

### 5.1 Structure

Each entry:

```json
{
  "canonical_parameter_id": "hba1c",
  "display_name": "HbA1c",
  "category": "Diabetes panel",
  "canonical_unit": "%",
  "range_type": "fixed_range",
  "typical_reference_range": { "low": 4.0, "high": 5.6 },
  "aliases": ["HbA1c", "Hb A1c", "Glycosylated Hemoglobin", "Glycated Hemoglobin (HbA1c)", "A1C", "GHb"],
  "plausible_range_for_validation": [2.6, 22.4]
}
```

- `range_type` is one of `fixed_range | open_upper_bound | open_lower_bound | interpretive_rule | qualitative` — see Section 4.6 for how each must be handled in the UI and validation logic. `typical_reference_range.high` (or `.low`) is `null` where a bound is intentionally unbounded, and the whole object is `null` for `interpretive_rule` and `qualitative` entries by design.
- `plausible_range_for_validation` is deliberately wider than the clinical normal range — it exists only to catch extraction errors (Section 4, stage 9), not to flag clinical abnormality.
- Where a real coding standard applies, treat `canonical_parameter_id` as a candidate to map to **LOINC** codes in a later phase (store a `loinc_code` field once that mapping work is done) — not required for v1, noted so the schema doesn't need to change later.

### 5.2 Coverage

119 parameters across 17 categories: Vitals, CBC (hematology — the largest single category, reflecting how much of a routine Indian annual-checkup panel this covers), Diabetes panel, Lipid panel, Liver function, Kidney function, Electrolytes, Thyroid panel, Vitamins, Iron studies, Cardiac markers, Inflammatory markers, Coagulation, Urine routine, Hormones, Serology, Cancer markers. This was originally built by cross-referencing standard Indian diagnostic-lab panels (the kind reflected in both reference reports) against common comprehensive/annual-checkup panels. Section 5.4 describes a subsequent verification pass against web sources; the dictionary now stands at 129 parameters across 18 categories (v1.1.0) and is still intended as a strong seed, not a closed, final list.

### 5.4 Web-research verification pass (v1.1.0) — methodology and findings

The v1.0.0 dictionary was built primarily from training-data knowledge of standard lab panels, cross-referenced against the two reference reports. It was explicitly *not* verified against live sources at that point. A follow-up pass corrected that by searching authoritative and semi-authoritative sources per category (Mayo Clinic, Cleveland Clinic, MedlinePlus, LabCorp/Quest-cited consumer ranges, StatPearls, NCEP ATP III/AHA lipid guidance, Geeky Medics clinical reference tables, ACP's published reference-range tables) and comparing every major panel against the seed values. Two findings should shape how Claude Code treats this dictionary going forward, not just this one update:

1. **Published reference ranges disagree with each other, sometimes by a meaningful margin, even among reputable sources.** WBC "normal" was cited as 4.5–11.0, 4.3–10.8, 4.1–10.9, and 3.8–10.5 (×10³/µL) across four different sources in the same search pass; ALT ranged from "0–35" to "7–55 (men) / 7–45 (women)" depending on the source and sex-adjustment. This is not a research gap to close with more searching — it's the actual state of the field, and it's exactly why Section 4.6's rule (a report's own printed range always wins over the dictionary default) matters more than it might first appear. The dictionary default is a reasonable fallback, not a ground truth.
2. **Several parameters have clinically meaningful sex-specific ranges that v1.1.0 still models as a single unisex band** — hemoglobin, hematocrit, RBC count, ferritin, uric acid, testosterone, estradiol, ALT/AST, and GGT all came back with visibly different male/female reference ranges during research. This version deliberately does not attempt to model per-sex (or per-age, e.g. pediatric or pregnancy-specific) ranges, to avoid shipping a half-verified stratified model — it's flagged in the dictionary's own `_meta.known_limitation` field as the next enhancement, and Claude Code should treat `Member.sex` and `Member.dob` (already in the data model, Section 10) as the fields that would drive that stratification when it's built, rather than adding new fields for it later.

Concretely, this pass corrected two modelling errors (HDL was wrongly given a fixed 40–60 band; corrected to `open_lower_bound` since higher HDL is protective, not abnormal above some cutoff — see the new `range_type` value in 5.1) and added 10 parameters common in comprehensive/annual panels that were missing entirely: Amylase, Lipase, D-Dimer, ANA, Anti-TPO Antibody, LH, FSH, Beta-hCG, BNP, and Ammonia. The full changelog is in the dictionary file's own `_meta.changelog` field — treat that field as authoritative over this section if they ever diverge, since the file is what actually ships.

### 5.3 The dictionary is expected to keep growing — build the governance for that, not just the seed data

Treat 119 as a starting point, not a ceiling. The two reference reports alone (a routine CBC panel from each of two labs) surfaced roughly 25 parameters not in an earlier, smaller draft of this dictionary — mostly extended CBC/differential-count detail. The next unfamiliar report type (a cardiac panel, an oncology marker panel, a fertility panel) will surface more. This is why Section 4.4's "no match → new-candidate" path and the `platform_admin` review queue are load-bearing product features, not an edge-case afterthought:

- Every unmatched extracted label becomes a candidate record (label as printed, value, unit, source document, member) visible to `platform_admin`.
- An admin resolves each candidate one of three ways: add it as a brand-new canonical parameter; add it as a new alias of an existing canonical parameter (the common case — most "new" candidates are just a naming variant); or mark it as a lab-specific derived index requiring clinical review before any automated interpretation is attached (Section 4.6).
- Version the dictionary. Every stored parameter value keeps a reference to which dictionary version was active when it was parsed, so a later correction to an alias list or a reference range doesn't silently reinterpret historical data without an explicit, auditable re-validation pass.

---

## 6. Trend Graphs & Year-over-Year Comparison

### 6.1 Trend graphs

- For any canonical parameter with 2+ confirmed (auto_accepted or member-confirmed) data points for a given member, render a line graph: x-axis = test date, y-axis = value, with the *resolved* reference range (Section 4.6 — printed range if available, else dictionary default) shown as a shaded band, and out-of-range points visually distinguished.
- `open_upper_bound` parameters shade only a lower boundary, never an artificial upper one.
- `interpretive_rule` parameters (Mentzer Index, RDWI) plot the raw value over time with **no shaded band and no automated in/out-of-range colour flag**, per Section 4.6.
- `qualitative` parameters (urine protein, HBsAg, etc.) do not get a numeric line graph at all — render as a simple status timeline (date → value label, e.g. "Nil", "Reactive") instead.
- Never blend two family members' data on one chart — every graph is per-member.
- Group parameters by `category` (from the dictionary) when showing multiple related graphs together (e.g. all Lipid panel parameters as small multiples in one section), so a 20-parameter annual panel reads as a handful of grouped sections, not 20 flat charts to scroll through.

### 6.2 Year-over-year comparison — the explicit "annual checkup" feature

This is a named requirement, not a side effect of trend graphs: a member must be able to pick two dates (typically "this year's checkup" vs. "last year's") and see every parameter that appears in both, grouped by category, with the prior value, the new value, the delta, and an in/out-of-range flag for the latest value (respecting range_type as above) — in one screen, not by opening 20 individual graphs. When picking a default comparison pair automatically (rather than the user choosing), prefer the two most recent dates that share the largest number of common parameters (a genuine repeat annual panel), not simply the two most recent dates overall (which might be two unrelated single-test uploads).

### 6.3 Qualitative/status timeline

For `qualitative` parameters, "graphing wherever possible" means a horizontal timeline of dated status values (e.g. HBsAg: Non-Reactive on three dates) rather than forcing a line chart onto non-numeric data. Don't skip these parameters from the trends UI entirely just because they can't be plotted as a line — a status change (e.g. a screening result flipping) is exactly the kind of thing a member or doctor would want visible over time.

---

## 7. Provider (Doctor Console) — Check-in, Consent, Unlock, Consult

This section consolidates the doctor-console BRD and its mockups into an implementation spec. The governing design principle: **the doctor sees nothing until two independent conditions are both true — the patient has physically checked in for this specific visit, and the patient has freshly, separately consented in real time.** A booking-time sharing preference is not a substitute for either.

### 7.1 Status flow (state machine)

```
scheduled → checked_in → consent_requested → consent_granted → in_consultation → completed
                              ↘ consent_denied           ↘ (access auto-revoked on completion)
                              ↘ consent_expired
```

- `scheduled → checked_in`: performed by front-desk staff or the doctor when the patient physically arrives. **Grants no data access** — it only makes the consent-request action available.
- `checked_in → consent_requested`: the doctor (or front desk) triggers a real-time consent request for this specific visit.
- Two consent paths, equally rigorous:
  - **In-app approval** (default): a push notification to the patient's (or family coordinator's) CareLoop app naming the requesting doctor and the visit; patient taps Approve or Deny.
  - **OTP fallback** (for patients without a smartphone — notably senior parents): an SMS OTP is sent to the patient's registered mobile; the patient reads it aloud and the doctor enters it into the console. This path must carry the same evidentiary/audit weight as in-app approval — it is a parity requirement, not a lesser workaround.
- A consent request expires after a configurable window (business default: 5 minutes, to be validated against real clinic timing before being locked in) if the patient doesn't respond; the doctor must explicitly resend, never wait indefinitely.
- `consent_granted`: full record access unlocks for this visit (7.2) and the grant is visible to both doctor and patient with timestamp and scope.
- `completed`: triggered when the doctor ends the visit. **Access is automatically and immediately revoked** — this is not standing access the doctor can return to later; a later visit requires a fresh check-in and a fresh consent grant.
- `consent_denied` / `consent_expired`: must be a visibly distinct state from "still waiting" — never leave the doctor unable to tell the difference between a slow patient and a refused request. Neither state unlocks any data — fail closed.

### 7.2 What "unlocked" means

Once `consent_granted`, the doctor sees, for that member, in one place: the summary card (allergies, chronic conditions, current medications), the full document/history timeline, and trend graphs — the complete picture needed to reason about root cause and treatment, not a partial view that forces a second request mid-visit. The console must display the grant's own timestamp and scope alongside the data, so the doctor sees the same trust signal the patient sees on their side.

### 7.3 Consultation workspace

Within an unlocked, `in_consultation` visit, the doctor can view relevant flagged history (out-of-range values since the last visit) alongside a notes field and a structured e-prescription builder (medicine name, strength, dosage, frequency, duration, free-text instructions). Completing the visit (a) marks it `completed`, (b) revokes access per 7.1, and (c) delivers the signed e-prescription directly into the member's own record — see Section 8 for exactly how that handoff works.

### 7.4 Audit, symmetrically

Every grant, denial, and revocation is logged (actor, timestamp, scope) and shown, in plain language, to **both** the doctor (in-context on the console) and the patient (in their own Consent & Privacy screen in the member app) — this symmetry is a product requirement, not just a compliance checkbox: trust requires both sides to see the same thing, not just a backend log neither of them can see.

### 7.5 What this document intentionally does not decide

- Whether front-desk staff (vs. only the doctor) may perform the check-in action — a clinic-operations question to confirm with a pilot clinic, not an engineering one; build the permission as configurable rather than hardcoding one answer.
- Any "emergency/break-glass" access path that bypasses this flow — explicitly out of scope; do not build a shortcut through the consent gate for any reason without a separately specified, separately audited emergency-access policy, which does not exist yet.

---

## 8. Member ⇄ Doctor Integration — How the Two Sides Actually Connect

This section exists because the member app and the doctor console are not two independent features that happen to share a database — they are two views onto one continuous event sequence. Implement this as one coherent flow, not two features integrated after the fact.

### 8.1 End-to-end sequence for a single visit

1. **Booking (member side).** The member books an appointment with a provider, optionally pre-setting a sharing preference (summary card vs. full history) for async prep. This preference does **not** grant any access by itself — it's a hint, not a permission (Section 7 makes this explicit; re-stated here because it's the seam between the two sides).
2. **Check-in (provider side).** On the visit day, front desk/doctor marks the patient checked-in once they arrive. The member app can optionally reflect this ("You're checked in for your 5:30 PM visit with Dr. Rao") but no data has moved yet.
3. **Consent request (provider triggers, member responds).** The doctor requests consent; the member's phone receives the in-app approval prompt (or the OTP fallback is used). This is the one moment in the whole flow where an action on one console produces an immediate, real-time UI event on the other — build this as a real-time channel (push notification + live status poll/subscription), not something the member only discovers by refreshing later.
4. **Unlock (provider side), mirrored (member side).** The moment consent is granted, the doctor's console unlocks (7.2) *and* the member's own Consent & Privacy log gets a new entry simultaneously — both are written from the same consent-grant event, not two independent writes that could drift out of sync.
5. **Consultation (provider side).** The doctor works entirely within the unlocked session (7.3).
6. **Prescription issued (provider writes, member receives).** The moment the doctor signs the e-prescription, it must appear in the member's own document timeline and medication history **without the member doing anything** — this is a trusted-source write directly into the member's structured data (Section 3.4), skipping the OCR/review pipeline entirely, since it originates as structured data from a verified provider action, not an image.
7. **Completion (provider triggers, both sides reflect it).** Marking the visit complete revokes access (7.1) *and* updates the appointment's status on the member side to "Completed" with the new prescription visible.

### 8.2 Why this must be one integrated data flow, not two

If the member app and doctor console are built against two different notions of "what's shared right now," they will drift — e.g. a doctor's console showing access as still active after the member has revoked it elsewhere, or a prescription that reaches the doctor's own records but not the member's. Concretely: **the `ConsentGrant`/appointment-status object is a single source of truth read by both sides**, not duplicated state. Any UI on either side is a read (and, for the specific actions each role is allowed, a write) against that one object, never a locally cached copy that could go stale.

### 8.3 What the member sees, at every step, from their own side

- Before consent: an appointment card showing status (Scheduled → Checked-in), no request yet.
- During request: a live approve/deny prompt naming the doctor and the reason ("Dr. Rao is requesting full access to your records for today's 5:30 PM visit").
- After granting: an entry in their audit log with exact timestamp and scope — identical in substance to what the doctor's console shows on its side (7.4).
- After the visit: the new prescription already sitting in their records, and the appointment marked Completed — they should never need to "go get" the prescription from anywhere.

---

## 9. Payer Integration (brief — retained for completeness)

Payers only ever see **derived risk signals** (e.g. "3 of 5 tracked cardiometabolic markers out of range, trend improving"), never raw documents, and only for members who have granted explicit, revocable, signal-level consent — there is no bulk or default payer access. Every payer view is logged and visible to the member in the same audit log as provider access (Section 7.4/8.3). Population-level payer dashboards must suppress any segment cut below a minimum member count (e.g. 10) to prevent re-identification. This module is lower priority than Sections 3–8 for initial delivery — build the consent/access-control layer generally enough (Section 10) that payer access is a thin addition on top of it, not a separate system.

---

## 10. Data Model (consolidated)

| Entity | Key fields |
|---|---|
| `Family` | family_id, primary_member_id |
| `Member` | member_id, family_id, name, dob, sex, blood_group, relationship_to_primary, login_credentials_ref (nullable) |
| `Allergy` / `ChronicCondition` | member_id, value, source_document_id |
| `Document` | document_id, member_id, uploaded_by, document_type, presentation_style, storage_uri, checksum, lab_visit_id, upload_date, source_lab_name |
| `ExtractedParameter` | id, document_id, member_id, canonical_parameter_id, raw_label_as_printed, value, unit, canonical_value, canonical_unit, printed_reference_range (nullable), resolved_reference_range, test_date, match_tier, confidence_score, review_status (`auto_accepted`/`pending_review`/`confirmed`/`corrected`), dictionary_version_at_parse_time |
| `NewParameterCandidate` | id, member_id, document_id, label_as_printed, value, unit, status (`pending`/`resolved_as_new_param`/`resolved_as_alias`/`resolved_as_interpretive_index`) |
| `CanonicalParameter` | (as in the dictionary JSON, Section 5.1) plus `dictionary_version` |
| `Provider` | provider_id, type, name, specialty, clinic_id |
| `Appointment` | appointment_id, member_id, provider_id, datetime, status (state machine, Section 7.1), sharing_preference, consent_grant_id |
| `ConsentGrant` | id, appointment_id, member_id, provider_id (or payer_id), method (`in_app`/`otp`), scope, granted_at, expires_or_revoked_at, denied (bool) — **single source of truth read by both member and provider UIs (8.2)** |
| `Prescription` | id, appointment_id, provider_id, member_id, line_items[], issued_at |
| `InsurancePolicy` | id, member_id, payer_id, policy_number, sum_insured, period, covered_member_ids[] |
| `RiskSignal` | id, member_id, payer_id, signal_type, trend_direction, computed_at — derived only, never embeds raw values |
| `AuditLogEntry` | actor_id, actor_role, action, target_member_id, timestamp — the source for both 7.4 and 8.3 |

---

## 11. Non-Functional Requirements

- Encryption at rest and in transit; documents served via short-lived signed URLs, never public buckets.
- Every extraction pipeline run is asynchronous and resilient — a failed parse falls back to "manual entry required," never silently drops the upload.
- Trend-graph and YoY-comparison queries should target sub-second response for one member's data — index `ExtractedParameter` by (member_id, canonical_parameter_id, test_date).
- Every read of member health data by a provider or payer is logged (Sections 7.4, 9).
- The canonical dictionary and its aliases/ranges are admin-editable data, not hardcoded application logic (Section 6 of the earlier platform PRD; restated here because Section 5.3 depends on it).

---

## 12. Instructions to Claude Code — How to Actually Build This

Read this section as direct build instructions, in order.

### 12.1 Recommended stack

- **Web app first, Android via Capacitor.** Build CareLoop as a modern web application (React or similar), then wrap it with [Capacitor](https://capacitorjs.com/) to produce the Android project and, ultimately, the APK. This avoids a slower, riskier full native rewrite while still producing a real installable Android app, and lets the same codebase serve a desktop-first provider/payer experience and a mobile-first member experience (per the original design intent).
- **Backend:** a role-aware REST or GraphQL API sitting in front of a relational database (Section 10's entities). Model `ExtractedParameter` with indexing suited to time-series access patterns (Section 11).
- **Extraction:** call a vision-capable LLM API for pipeline stage 4 (Section 4.3) rather than building a custom OCR+regex system — this is the single most important stack decision in the whole build, because it's what makes the layout-agnostic requirement (Section 4.1) achievable at all.
- **Real-time consent flow (Section 7.1, 8.1):** use a push-notification service plus a live subscription/poll for the consent-request state, so the doctor's console updates the moment the member responds without a manual refresh.

### 12.2 Build order

1. Family/member data model (Section 3.1) + auth/role resolution (Section 2).
2. Document upload + the full parsing pipeline (Section 4) against the seed dictionary (companion JSON, Section 5) — get this right before building anything downstream, since trend graphs, YoY comparison, and the doctor console's "flagged history" all depend on it being correct.
3. Trend graphs + YoY comparison (Section 6).
4. Appointment booking + the check-in/consent/unlock/consult/complete state machine (Section 7) + the member-doctor integration as one shared data flow, not two features (Section 8).
5. Payer module (Section 9) — only after 1–4 are solid and the consent/access-control layer is proven correct, since payer access is the highest-risk surface.
6. Package with Capacitor and produce the Android build (12.3).

### 12.3 Getting to the APK

```
# after the web app builds and runs correctly on its own:
npm install @capacitor/core @capacitor/android
npx cap init CareLoop <your-app-id>
npx cap add android
npx cap sync android
cd android
./gradlew assembleDebug     # produces app/build/outputs/apk/debug/app-debug.apk
```

A release/signed build requires a keystore and `./gradlew assembleRelease` — set this up once a debug build is verified working, and treat signing-key management as a deployment concern, not something to improvise inline. If the environment you're building in has no Android SDK available, stop after confirming the web app is fully working, explain that clearly (per Section 0), and hand back a project where these exact commands are the only remaining step.

### 12.4 Testing expectations before calling any milestone done

- Run the golden test set (Section 4.8), starting with the two reference reports, after any change to extraction, matching, or the dictionary.
- Verify the Section 7.1 state machine cannot be short-circuited — write an explicit test that access is denied at every state except `consent_granted`/`in_consultation`, and that it's revoked immediately on `completed`.
- Verify a `qualitative` or `interpretive_rule` parameter never renders a numeric in/out-of-range flag (Section 4.6/6.1) — this is a clinical-safety check, not just a UI nicety.

---

## 13. AI Agents & MCP Architecture

Everything specified so far (Sections 4–9) is deterministic pipeline logic and gated state machines — parsing, matching, consent, access control. This section identifies where genuinely agentic behavior (multi-step reasoning over the data those pipelines produce) adds value on top of that foundation, and which external MCP connectors an agent or the app itself would call. Treat this as an extension layer, not a replacement for anything already specified — every agent below reads from or writes to the data model in Section 10 and must respect the access-control rules in Section 11 exactly like any other part of the app.

**The one rule every agent in this section inherits, without exception:** an agent drafts, summarizes, flags, and prepares — a human (the member, the doctor, or the payer's underwriter) confirms and acts. None of these agents makes an autonomous clinical or underwriting decision. This is the same constraint already governing `interpretive_rule` parameters (Section 4.6) and payer risk signals (Section 9/BR-16 in the doctor-console BRD) — this section doesn't introduce a new principle, it applies the existing one to a new capability.

A companion document, `CareLoop_Agents_MCP_Roadmap.md`, gives the full inventory with build priority, complexity, and dependencies. This section is the summary that belongs in the main build spec.

### 13.1 Agent inventory (by actor)

| Agent | Actor | What it does | Reads / writes |
|---|---|---|---|
| Document intake agent | Member | The Section 4 parsing pipeline itself, framed as an agent — classify → extract → match → validate → route | `Document`, `ExtractedParameter` |
| Health insights agent | Member | Drafts a plain-language "what changed since last time" summary for the Health Analysis tab | Reads `ExtractedParameter`; writes nothing structured, output is display-only text |
| Family care-coordinator agent | Member | Proactively flags overdue checkups, medication refills, vaccination due-dates across the whole family | Reads across all `Member` profiles in a `Family` |
| Symptom intake agent | Member | Structures a free-text Symptoms & Observations entry via clarifying questions; never suggests a diagnosis | Writes to the symptom log only |
| Consent explainer agent | Member | Plain-language explanation of a consent request before the member approves it (Section 7.1) | Reads `ConsentGrant` request context only |
| Pre-visit prep agent | Provider | Summarizes flagged history into a one-screen brief the moment `consent_granted` fires (Section 7.2) | Reads `ExtractedParameter`, `Document` for the unlocked member only |
| Medication reconciliation agent | Provider | Checks a draft e-prescription against allergies/current medications before the doctor signs it | Reads `Allergy`, `Prescription`; flags conflicts, never blocks or auto-edits |
| Risk-signal drafting agent | Payer | Drafts observations on the population dashboard for a human underwriter | Reads `RiskSignal` only — never `ExtractedParameter` or `Document`, per Section 9 |
| Dictionary curation agent | Platform admin | Flags reference-range drift against current sources; pre-drafts alias-vs-new-parameter resolutions for the review queue | Reads/proposes against `CanonicalParameter`; `platform_admin` approves, never auto-applies |

### 13.2 MCP connectors

| Connector | Purpose | Feeds |
|---|---|---|
| Calendar (Google/Outlook) | Push appointment bookings to the member's own calendar | Appointment booking (Section 7) |
| Email | Detect lab-report PDFs arriving as attachments and offer one-tap import | Document intake agent |
| WhatsApp Business | Accept a forwarded report photo as an upload channel — high-relevance for the India market this app targets | Document intake agent |
| Pharmacy partner APIs (1mg, PharmEasy, Apollo) | One-click medicine ordering | Explicitly Phase-4/later (Section 13, out-of-scope list) — connector should be stubbed, not built, until that phase |
| Lab-chain APIs (Thyrocare, Dr Lal PathLabs, Metropolis) | Structured results direct from source, bypassing OCR entirely for that lab | Document intake agent (trusted-source shortcut, same pattern as provider-issued e-prescriptions in Section 3.4) |
| ABDM/ABHA | National health-ID record exchange | Already flagged as future scope (Section 13/14) — this is the connector that scope would use when built |
| Maps/places | Provider/clinic search by location | Appointment booking (Section 7) |

### 13.3 Build priority (summary — full detail in the companion roadmap)

Build order should follow the same logic as Section 12.2: nothing agentic ships before the deterministic pipeline and consent gates it depends on are solid. In brief — document intake agent and health insights agent are viable early (they sit directly on top of Section 4–6, already first-priority build targets); pre-visit prep and medication reconciliation agents follow once the doctor console (Section 7) is stable; the risk-signal drafting agent is last, matching Section 12.2's existing guidance that payer features are the highest-risk surface and come only after the consent/access-control layer is proven. See the companion roadmap for the full phasing, complexity estimates, and MCP build-vs-defer calls.

---

## 14. Explicitly Out of Scope for This Build

- Government health-ID (ABDM/ABHA) integration — noted as a future alignment opportunity, not a v1 commitment.
- One-click pharmacy checkout/payment/delivery — build the `Prescription` data model so this can be added later, but do not build fulfillment in this pass.
- Any emergency/break-glass access path around the consent gate (Section 7.5).
- Automated clinical interpretation of `interpretive_rule` parameters without clinician sign-off (Section 4.6) — under no circumstances infer or ship this logic unilaterally.
- Non-English/regional-language report parsing and handwriting-heavy prescriptions beyond what the golden test set validates — flag as a known gap rather than silently under-performing on it.
- Any agent (Section 13) making an autonomous clinical or underwriting decision, or auto-applying a dictionary change without `platform_admin` approval — every agent in Section 13 drafts for a human, full stop.
- Pharmacy-partner and ABDM MCP connectors (Section 13.2) — stub only, matching the fulfillment and government-ID items above.
