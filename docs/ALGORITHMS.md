# How Nine30 calculates its scores

Nine30 is a personal build of [Pulsr](https://github.com/0xCodez/pulsr). Changes from Pulsr are marked **(Nine30)**.

All formulas live in [`Shared/ScoreEngine.swift`](../Shared/ScoreEngine.swift). They are transparent, simple and tunable — improvements backed by research are very welcome.

## Inputs (from Apple Health)

| Metric | HealthKit type | Used for |
|---|---|---|
| Heart rate, per-minute average | `heartRate` | Strain, zones, stress |
| HRV (SDNN) during sleep | `heartRateVariabilitySDNN` | Recovery |
| Resting heart rate | `restingHeartRate` | Recovery, strain, body age |
| Respiratory rate during sleep | `respiratoryRate` | Recovery, health monitor |
| Sleep stages | `sleepAnalysis` | Sleep, recovery |
| Wrist temperature, SpO₂ | `appleSleepingWristTemperature`, `oxygenSaturation` | Health monitor |
| VO₂ max, steps, active energy, workouts | various | Body age, strain detail |

A night belongs to the day you woke up (sleep samples starting between 15:00 the previous day and 15:00). If several sources recorded the same night, the one with the most staged sleep wins. Nights under 2 h are treated as naps and ignored.

## Baselines

For each day, the previous 30 days form the baseline (mean and SD). While there are few nights, the baseline is shrunk toward a population prior with a weight of 4 nights:

- ln(HRV): mean ln 45 ms, SD 0.30
- RHR: 60 ± 5 bpm
- Respiratory rate: 15 ± 1 /min

Scores are marked *calibrating* until 7 nights of HRV exist.

**(Nine30)** A night's HRV is the **median** of the SDNN readings taken during sleep (Pulsr used the mean), so one noisy reading cannot move the night.

## HRV trend and range (Nine30)

```
trend  = mean of ln HRV over the last 7 days (at least 3 nights)
range  = exp(mean ± 0.5·SD)          the "smallest worthwhile change" band
status = below / typical / above      trend compared with the range
```

The trend, not a single night, decides whether HRV is typical (the approach used in HRV-guided training research, e.g. Plews et al.).

## Confidence (Nine30)

```
points = 2 if ≥ 5 HRV readings last night, 1 if ≥ 3
       + 2 if ≥ 21 nights of baseline, 1 if ≥ 7
       + 1 if a 7-day trend exists
high ≥ 4 · medium ≥ 2 · low otherwise (and always low with no HRV last night)
```

## Recovery (0–100 %)

```
z_hrv  = 0.5·z(last night) + 0.5·z(7-day trend)    each clamped ±3   (Nine30; Pulsr used last night only)
z_rhr  = −(RHR − mean) / SD                         clamp ±3
z_resp = −|resp − mean| / SD                        clamp 0…3
z_sleep = (sleepPerformance − 0.85) / 0.12          clamp −3…2

composite = (0.55·z_hrv + 0.25·z_rhr + 0.05·z_resp + 0.15·z_sleep) / (sum of available weights)
recovery  = 100 / (1 + e^−(1.25·composite + 0.35))
```

An average night lands around 59 %. Zones: green ≥ 67, yellow 34–66, red < 34.

## Strain (0–21)

Per minute of heart rate (gaps ≤ 10 min are linearly interpolated, because the watch samples every few minutes outside workouts):

```
HRR  = (HR − RHR) / (HRmax − RHR)            only minutes with HRR ≥ 0.25 count
TRIMP += HRR · a · e^(b·HRR)                 a, b = 0.64, 1.92 (male) · 0.86, 1.67 (female)   — Banister 1991
strain = 21 · (1 − e^(−TRIMP / 125))
```

HRmax = 208 − 0.7 · age (Tanaka 2001) unless set manually. Zones are 50/60/70/80/90 % of HRmax.

Strain target by recovery: green 14–18, yellow 10–14, red 4–10.

## Sleep

```
debt = max(0, Σ over last 14 nights of  w · (goal − asleep))      w = 1 for last night … 1/14 two weeks ago
       nights above goal pay debt back; nights with no data are skipped            (Nine30)

need = goal (default 7 h 45)
     + 0.06 h × (yesterday's strain − 10)              if strain > 10
     + 0.2 × yesterday's sleep debt                    capped at 1 h      (Nine30; Pulsr used 0.25 × 3 nights' shortfall)

hoursVsNeeded = min(1, asleep / need)
efficiency    = asleep / time between first and last sleep sample
consistency   = 1 − mean(|bedtime Δ|, |wake Δ| vs. previous 4 nights) / 120 min
performance   = 100 · (0.6·hoursVsNeeded + 0.2·consistency + 0.2·efficiency)
```

Recommended bedtime = average wake time of the last 7 days − need / 0.92.

## Stress (0–3)

Outside workouts, every heart-rate sample becomes `3 · clamp((HR − RHR − 5) / (0.35 · (HRmax − RHR)), 0, 1)`; during sleep it is scaled down. Values are averaged into 15-minute buckets. Low < 1, medium 1–2, high ≥ 2.

## Body Age

Starts at your age and adds years for each factor (each clamped):

| Factor | Years |
|---|---|
| VO₂ max vs. age/sex norm | −0.45 per ml/kg/min above norm |
| Resting HR | +0.15 per bpm above 62 |
| HRV vs. age norm | −0.06 per ms above norm |
| Sleep duration | +1.2 per hour under 7 h, −0.5 otherwise |
| Sleep consistency | +4 × (0.8 − consistency) |
| Daily steps | −0.25 per 1 000 above 7 000 |
| Zone 2–3 minutes / week | −0.4 per hour above 150 min |

Total is capped at ±12 years. This is a motivational estimate, not a clinical biomarker.

## Journal impact

For each behavior: mean next-day recovery after "yes" days vs. "no" days, as a percentage change. Needs at least 3 of each.
