# DashboardV2 — Metric Definitions (v1)

**Purpose**: Semantic contract for all DashboardV2 metrics. If a metric cannot satisfy all fields below, it does not belong on the dashboard.

**Timezone**: Asia/Dubai (UTC+4) for all date boundaries.

---

## Recovery Score

**Primary Question**: "How ready is my body to perform today?"

**Source of Truth**: `health.whoop_recovery.recovery_score` (WHOOP via Home Assistant)

**Update Cadence**: HA polls WHOOP every 15 minutes; value updates once per night (upon waking)

**Time Window**: Single day (today). WHOOP assigns recovery to the day you wake up.

**Inclusion Rules**: Most recent recovery record for `canonical_date = today`

**Exclusion Rules**: None

**Failure/Staleness Conditions**:
- `hours_since_sync > 24`: Stale
- No WHOOP worn: NULL (show "No data")
- HA integration offline: Uses last known value

**Interpretation Guidance**: <67 = compromised (reduce intensity). >80 = green (train hard). Do not compare across users. Recovery reflects HRV trend, not absolute fitness.

---

## Sleep Duration

**Primary Question**: "Did I get enough sleep last night?"

**Source of Truth**: `health.whoop_sleep.total_sleep_minutes` (WHOOP)

**Update Cadence**: Same as Recovery (morning sync)

**Time Window**: Previous night's sleep, assigned to today's date

**Inclusion Rules**: `total_sleep_minutes` from most recent sleep record

**Exclusion Rules**: Naps (if WHOOP separates them)

**Failure/Staleness Conditions**:
- Missing sleep record: NULL
- WHOOP removed during night: Partial data, may undercount

**Interpretation Guidance**: Target 7-8h. <6h multiple days = accumulated debt. Deep + REM more important than total. This metric alone does not indicate sleep quality.

---

## Daily Strain

**Primary Question**: "How hard did I push my body today?"

**Source of Truth**: `health.whoop_strain.day_strain` (WHOOP)

**Update Cadence**: Continuous during day, finalizes at midnight

**Time Window**: Current calendar day (Dubai TZ)

**Inclusion Rules**: Latest strain value for today

**Exclusion Rules**: None

**Failure/Staleness Conditions**:
- Mid-day value will increase; only final (post-midnight) is accurate
- WHOOP not worn: 0 strain (misleading)

**Interpretation Guidance**: 0-9 = light, 10-13 = moderate, 14-17 = strenuous, 18+ = all out. Match strain to recovery. High strain + low recovery = overtraining risk.

---

## Weight

**Primary Question**: "What is my current body weight trend?"

**Source of Truth**: `health.metrics` WHERE `metric_type = 'weight'` (Eufy Scale → Apple Health → iOS app)

**Update Cadence**: On iOS app open (HealthKit sync)

**Time Window**: Most recent measurement, plus 7d/30d delta

**Inclusion Rules**: Latest weight record

**Exclusion Rules**: None

**Failure/Staleness Conditions**:
- No weigh-in for 7+ days: Show last known with "X days ago" warning
- Multiple weigh-ins same day: Use first (morning)

**Interpretation Guidance**: Single readings are noise. Track 7-day moving average. Weight fluctuates 1-2kg daily from water/food. Compare week-over-week, not day-over-day.

---

## Monthly Spend

**Primary Question**: "How much have I spent this month vs my typical pattern?"

**Source of Truth**: `finance.transactions` WHERE `amount < 0` (Bank SMS import)

**Update Cadence**: Near real-time (SMS watcher triggers on new message)

**Time Window**: Current calendar month (Dubai TZ)

**Inclusion Rules**:
- `amount < 0` (expenses only)
- `is_quarantined = false`
- `date` within current month

**Exclusion Rules**:
- Income (`amount > 0`)
- Quarantined transactions
- Transfers between own accounts (if tagged)

**Failure/Staleness Conditions**:
- SMS import disabled: Stale (check `feed_status.transactions`)
- Offline queue not flushed: Undercounts manual entries
- Duplicate SMS: Overcounts (idempotency bug exists)

**Interpretation Guidance**: Use for early overspend detection, not final accounting. Does not include cash or untracked cards. Compare to same period last month, not arbitrary budgets.

---

## Grocery Spend

**Primary Question**: "Am I overspending on groceries this month?"

**Source of Truth**: `finance.transactions` WHERE `is_grocery = true`

**Update Cadence**: Same as Monthly Spend

**Time Window**: Current calendar month

**Inclusion Rules**: Transactions with `is_grocery = true` (set by merchant rules)

**Exclusion Rules**: Transactions miscategorized as grocery (rule accuracy issue)

**Failure/Staleness Conditions**:
- New grocery merchant not in rules: Undercounts
- Rule matches non-grocery: Overcounts

**Interpretation Guidance**: Accuracy depends on `merchant_rules` coverage. Check uncategorized transactions weekly. This is an estimate, not audit-grade.

---

## HRV (Heart Rate Variability)

**Primary Question**: "Is my nervous system recovering or stressed?"

**Source of Truth**: `health.whoop_recovery.hrv_rmssd_ms` (WHOOP)

**Update Cadence**: Morning (with recovery)

**Time Window**: Single night measurement

**Inclusion Rules**: HRV from most recent recovery record

**Exclusion Rules**: None

**Failure/Staleness Conditions**: Same as Recovery Score

**Interpretation Guidance**: Higher = better parasympathetic tone. Personal baseline matters more than absolute number. 10%+ drop from 7d avg = potential stress/illness. Do not compare to other people's HRV.

---

## Feed Status (Meta-Metric)

**Primary Question**: "Can I trust the data I'm seeing?"

**Source of Truth**: `ops.feed_status` view (derived from last sync timestamps)

**Update Cadence**: Computed on each dashboard request

**Time Window**: N/A (point-in-time check)

**Inclusion Rules**: All monitored feeds (whoop_recovery, whoop_sleep, whoop_strain, weight, transactions)

**Exclusion Rules**: None

**Failure/Staleness Conditions**:
- `healthy`: < 24h since sync
- `stale`: 24-72h since sync
- `critical`: > 72h since sync

**Interpretation Guidance**: If any feed is stale/critical, metrics depending on it are unreliable. Dashboard should show warning banner. Do not make decisions based on stale data.

---

## Metrics NOT on DashboardV2 (and why)

| Metric | Reason Excluded |
|--------|-----------------|
| Steps | Not persisted server-side; HealthKit local only |
| Calories consumed | Inconsistent logging; too noisy |
| Mood/Energy | Subjective; no actionable threshold |
| Sleep efficiency | Not populated by current WHOOP integration |
| RHR | Redundant with Recovery; less actionable |

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| v1 | 2026-01-22 | Initial contract |
