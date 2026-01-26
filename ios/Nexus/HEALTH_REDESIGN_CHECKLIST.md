# Health Tab Redesign - Smoke Test Checklist

## Build Verification
- [ ] Project builds without errors
- [ ] No SourceKit warnings for new Health views
- [ ] App launches and Health tab appears

## Today Segment
- [ ] Recovery card shows ring + percentage (color-coded: green >66%, yellow 34-66%, red <34%)
- [ ] Recovery card shows HRV, RHR, Strain with WHOOP source badge
- [ ] Sleep card shows hours/mins with efficiency percentage
- [ ] Sleep stages bar renders (Deep/REM/Light)
- [ ] Sleep comparison badge shows vs 7-day avg
- [ ] Activity card shows steps with HealthKit badge
- [ ] Body card shows weight in kg with HealthKit badge
- [ ] Finance context shows spend line (optional)
- [ ] Empty states display when data is missing
- [ ] Loading shimmer shows while data loads
- [ ] Pull-to-refresh works

## Trends Segment
- [ ] Period selector shows 7/14/30 days
- [ ] Switching periods updates all trend cards
- [ ] Sleep trend card shows avg hours + sparkline
- [ ] Recovery trend card shows avg % + sparkline
- [ ] Weight trend card shows kg + 30d delta
- [ ] Activity consistency shows days tracked (X/7)
- [ ] Sparklines render correctly (not flat lines)
- [ ] Empty state shows when no trend data

## Insights Segment
- [ ] Max 3 insights display (never more)
- [ ] Each insight has icon, title, detail, confidence badge
- [ ] Confidence badges color-coded (Early=orange, Moderate=blue, Strong=green)
- [ ] "Collecting data" state shows when insights empty
- [ ] Progress indicator shows days tracked this week
- [ ] Data Sources section shows WHOOP and HealthKit status
- [ ] Pull-to-refresh reloads insights

## Health Sources View (via antenna icon)
- [ ] Navigation link works from toolbar
- [ ] WHOOP section shows connection status + last sync
- [ ] WHOOP metrics badges display (Recovery, HRV, RHR, Sleep, Strain)
- [ ] HealthKit section shows authorization status
- [ ] HealthKit metrics badges display (Steps, Active Energy, Weight, etc.)
- [ ] Sample count displays when > 0
- [ ] Sync Now button works (shows spinner during sync)
- [ ] Data Priority section explains WHOOP vs HealthKit rules
- [ ] Notes section displays deterministic source rule

## Data Trust
- [ ] WHOOP data shows orange W badge
- [ ] HealthKit data shows red heart badge
- [ ] No data mixing confusion
- [ ] Source attribution clear on every metric

## Design Quality
- [ ] Colors match app theme (.nexusHealth used appropriately)
- [ ] No hardcoded colors outside design system
- [ ] Cards have consistent corner radius (16pt)
- [ ] Proper spacing between elements
- [ ] Font weights consistent (bold for numbers, regular for labels)
- [ ] Calm, trustworthy aesthetic (no anxiety-inducing elements)

## Edge Cases
- [ ] App works with no WHOOP data
- [ ] App works with no HealthKit data
- [ ] App works with both data sources
- [ ] App handles API errors gracefully
- [ ] Cached data loads when offline
