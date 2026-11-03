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
- [ ] First build on PAK's iPhone and watch (needs Xcode run)

## Stage 2 · Daily use
- [ ] Morning check-in: 60 s HRV (RMSSD from heartbeat series), readiness 1–5, tags
- [ ] Body check: alert when 2+ vitals are out of range
- [ ] Range bands on every vital (Typical / Outlier)
- [ ] Status switch: Normal / Sick / Travel (sick and travel days stay out of baselines)
- [ ] HRV method setting: morning RMSSD / Apple overnight / SDNN

## Stage 3 · Deeper views
- [ ] Focus windows vs market hours (energy schedule from sleep timing)
- [ ] Training balance: fitness, fatigue, form, acute:chronic
- [ ] Energy through the day
- [ ] Market-hours stress lens + trading tags
- [ ] Habit impact with ranges, 10+ days each side, adjusted for prior strain
- [ ] Siri and Shortcuts (App Intents)

## Stage 4 · Wrist
- [ ] Watch app restyle
- [ ] Complications and Smart Stack widget

## After 4–6 weeks of live use
- [ ] Fit Recovery weights to check-in ratings
- [ ] Resilience (14-day balance)
- [ ] "Followed the plan" streak
- [ ] Timed nudges (caffeine cutoff, light, wind-down)
