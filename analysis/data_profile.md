# Verified data profile

Generated from the supplied CSV and the tested PostgreSQL analysis. See `audit.json`, `verification.json`, and `query_results.json` for reproducible evidence.

## Cleaning and identity

The input contains 3,631 data rows and two embedded headers. Removing 88 extra exact duplicates leaves 3,543 observations. The original schedule/class/count key plus collection date has 145 collision groups. The expanded visible-offer identity creates 585 offers while retaining all 108 offer/date groups with multiple prices.

A collision group is a group with more than one distinct source row under the original Flight natural key plus scrape date. It is not the number of discarded rows. In this dataset all 145 such groups also contain multiple prices.

## Matched changes on adjacent collection dates

Each comparison uses the daily minimum for one unchanged offer and includes it only if present in both adjacent collection runs. No missing runs are bridged. There are 2627 matched transitions; offers may appear in several transitions.

| Source class | Transitions | Increases | Decreases | Unchanged |
|---|---:|---:|---:|---:|
| Economy | 469 | 221 | 118 | 130 |
| Economy(Basic) | 1298 | 641 | 277 | 380 |
| Economy(Premium) | 860 | 384 | 106 | 370 |

## Movements by booking window

Booking windows are assigned using the newer observation. Median change includes zero changes and decreases; it is not the median of increases alone. Amounts use the project's CAD assumption.

| Source class | Days before departure | Matched transitions | Median change |
|---|---|---:|---:|
| Economy | 0-7 | 42 | 34.50 |
| Economy | 8-14 | 92 | 14.00 |
| Economy | 15-21 | 85 | 0.00 |
| Economy | 22-30 | 111 | -3.00 |
| Economy | 31+ | 139 | 0.00 |
| Economy(Basic) | 0-7 | 95 | 49.00 |
| Economy(Basic) | 8-14 | 255 | 9.00 |
| Economy(Basic) | 15-21 | 259 | 9.00 |
| Economy(Basic) | 22-30 | 349 | 0.00 |
| Economy(Basic) | 31+ | 340 | 0.00 |
| Economy(Premium) | 0-7 | 62 | 8.50 |
| Economy(Premium) | 8-14 | 153 | 45.00 |
| Economy(Premium) | 15-21 | 169 | 7.00 |
| Economy(Premium) | 22-30 | 232 | 0.00 |
| Economy(Premium) | 31+ | 244 | 0.00 |

Increases outnumber decreases in each class over these matched intervals. For example, Basic offers in the 0–7 day window have 84 increases, one decrease, and ten unchanged transitions, with a median change of CAD 49. These results describe the observed listings; they do not establish an optimal booking strategy.

## Interpretation limits

- Collection intervals vary from one to four days; changes are not standardized daily rates.
- Matching controls visible offer attributes, but not unobserved fare rules or inventory.
- Carrier order is canonicalized as a set; connection order is preserved.
- One departure week and two airport pairs cannot establish general weekday or market-wide patterns.
- Daily minima summarize ambiguous multiple-price listings; all distinct prices remain available for alternative analyses.
- Arrival/departure timestamps are local times, so elapsed flight duration is not calculated.
