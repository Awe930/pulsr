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
high = 5 · medium ≥ 3 · low otherwise (and always low with no HRV last night)
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
balance = min(+3 h, Σ over last 14 nights of  w · Δ)   Δ = asleep − goal, halved when positive
          w = 1 for last night … 1/14 two weeks ago
          positive = surplus, negative = debt; nights with no data are skipped        (Nine30)
          |balance| < 30 min shows as "On target"
debt    = max(0, −balance)

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

## Morning check-in and HRV method (Nine30)

A 1-minute Breathe session on the watch records beat-to-beat data. Nine30 reads the latest series from the last 3 hours:

```
RR intervals from beat times; drop RR outside 300–2000 ms and jumps > 20% from the previous beat (artifacts)
RMSSD = √ mean( (RRᵢ − RRᵢ₋₁)² )        needs ≥ 30 clean differences
```

HRV method **Morning check-in** (default): Recovery's HRV term is the z-score of ln(morning RMSSD) against your
morning baseline, once 7 mornings exist. On days without a reading it falls back to overnight SDNN (last night + 7-day trend).
Z-scores are unitless, so both feed the same Recovery formula. A morning reading counts as 2 confidence points.

## Day status (Nine30)

Days marked **Sick** or **Travel** at check-in are left out of every baseline (HRV, RHR, respiration, temperature, RMSSD).
Sick days set the strain target to 0–8. Readiness (1–5) is stored for fitting the Recovery weights after 4–6 weeks.

## Body check (Nine30)

Each vital is compared with your ±2 SD normal range. Two or more out of range at once shows the Body check alert
(the Apple Vitals rule: one odd reading is noise).
