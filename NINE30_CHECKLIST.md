# Nine30 build checklist

Running list for PAK's personal build of Pulsr. Updated with every push.

## Stage 1 · Foundation
- [x] Rename to Nine30 (app name, watch label, bundle IDs `$(BUNDLE_ID_PREFIX).nine30`)
- [x] Sentence case everywhere, no letter-spaced caps
- [x] Zone colours from the design canvas; neutral insight card with a zone dot
- [x] Smaller orb inside a recovery ring (zone colour)
- [x] Confidence chip under the score
- [x] Median nightly HRV + reading count
- [x] 7-day HRV trend and normal range; Recovery blends last night with the trend
- [x] 14-night weighted sleep debt as the headline sleep number
- [x] Strain shown out of 21 with today's target
- [x] New app icon (9:30 + gold ring; iOS can't recolour it daily without a pop-up, so it stays static)
- [x] First build on PAK's iPhone, Nov 3 (built on the 2019 MacBook Pro with Xcode 26.6; watch app unhooked until stage 4)

## Stage 2 · Daily use (pushed Nov 3, needs first build)
- [x] Morning check-in: 60 s HRV (RMSSD from a Breathe session's heartbeat series), readiness 1–5, day status; tags stay in the Journal
- [x] Body check: alert when 2+ vitals are out of range
- [x] Range bars on every vital in Body check
- [x] Status switch in the check-in: Normal / Sick / Travel (left out of baselines; sick = strain 0–8)
- [x] HRV method setting: Morning check-in (RMSSD, default) / Overnight (Apple SDNN)

## Stage 3 · Deeper views (3a and 3b pushed Nov 3)
- [x] Focus windows vs market hours (Today strip + Focus and energy screen)
- [x] Training balance: fitness, fatigue, form, acute:chronic (Trends tab)
- [x] Energy through the day
- [x] Market-hours stress card (tags done in stage 2)
- [x] Habit impact in points with ~95% ranges, 10+ days each side, adjusted for that day's strain
- [x] Siri and Shortcuts: recovery and focus window

## Stage 4 · Wrist (deferred Nov 3: watch is on watchOS 27; Xcode 26.6 on the 2019 can't install to it. Needs the M2 with ~20 GB free, then XcodeGen for complications)
- [ ] Watch app restyle
- [ ] Complications and Smart Stack widget

## After 4–6 weeks of live use
- [ ] Fit Recovery weights to check-in ratings
- [x] Resilience (14-day balance, Trends tab)
- [x] "Followed the plan" streak (Today)
- [x] Reminders: wind down (1 h before bedtime) and morning check-in (30 min after waking); caffeine cutoff skipped by PAK

## Fixes from first live run (Nov 3)
- [x] 30-day Avg Strain was diluted by days with no heart-rate data (only 14 days loaded); now loads 35 days and skips empty days
- [x] Confidence "high" now needs 5+ HRV readings (3 readings showed as high)
- [x] Confidence bars use the zone colour (were hard to see on light glass)

## Stage 2a · Sleep balance and appearance (Nov 3)
- [x] Sleep balance against the 7 h goal: debt, "On target" (±30 min) or surplus (capped at +3 h); debt raises tonight's need, surplus never lowers it
- [x] Appearance setting: Match phone / Light / Dark (Settings, top section)
- [x] Confidence chip shortened to one line ("3 readings · 30 nights")
- [x] Journal: Trading day and Big loss day tags
- [x] Sleep card shows last night next to the 14-night balance ("Surplus · last +0:41")
- [x] Surplus nights count at half weight (debt full); revisit with readiness data
- [x] Strength load: 0.6 TRIMP per strength minute
