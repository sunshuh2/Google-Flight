# Flight Price Analysis

A flight price tracking and analysis project built with **PostgreSQL**. It stores Google Flights search results, maintains price history, and compares fares by cabin class, booking window, carrier, and itinerary.

## Project Functions

- **Store flight offers:** Record departure and arrival airports, travel dates, flight times, carriers, connections, cabin class, and baggage allowances.
- **Track historical prices:** Keep prices collected on different dates for each offer, including multiple prices observed on the same date.
- **Import flight data:** Validate CSV records and load new observations without adding duplicate entries.
- **Compare fares over time:** Follow the same offer across consecutive collection dates and measure price increases, decreases, and unchanged fares.
- **Analyze booking windows:** Compare prices at different numbers of days before departure and identify when each offer reached its lowest recorded price.

## Dataset

The project contains **3,543 distinct price observations**, **585 flight offers**, and **11 collection dates**.

| Detail | Coverage |
|---|---|
| Collection period | December 29, 2025–January 30, 2026 |
| Departure dates | February 2–8, 2026 |
| Departure airports | Toronto Pearson (YYZ), Billy Bishop Toronto City (YTZ) |
| Destination airport | Vancouver International (YVR) |
| Connection airports | YEG, YLW, YOW, YQR, YUL, YWG, YXE, YYC |
| Cabin categories | Economy (Basic), Economy, Economy (Premium) |
| Itineraries | Nonstop, one-stop, and two-stop |

## PostgreSQL Database

The database organizes flight information into six related tables:

| Table | Purpose |
|---|---|
| `flight_offer` | Stores each offer's route, schedule, cabin class, baggage allowances, and identifying attributes. |
| `price_observation` | Stores prices and collection dates for each offer. |
| `airport` | Stores departure, arrival, and connection airport codes. |
| `carrier` | Stores carrier labels. |
| `transfer` | Links offers to connection airports in travel order. |
| `operating_airline` | Links offers to their associated carriers. |

Offers are distinguished by their schedule, airports, carriers, connections, cabin class, and baggage allowances. Each offer can have many historical price observations. Database constraints maintain valid records and relationships, while indexes support searches and price-history queries.

## Analyses

### Prices by Cabin Class and Booking Window

Compares average prices, median prices, and price ranges across cabin categories and five booking windows: 0–7, 8–14, 15–21, 22–30, and 31 or more days before departure.

### Price Changes Over Time

Compares the same offer on adjacent collection dates. It reports the number of increases, decreases, and unchanged fares, together with absolute and percentage price changes by cabin class and booking window. Comparisons use the lowest recorded price for each offer on each collection date.

### Lowest Recorded Fares

Identifies each offer's lowest observed price and how many days before departure it was available.

### Carrier and Itinerary Comparisons

Compares carrier combinations within cabin categories and booking windows, and examines price differences between nonstop and connecting itineraries.

### Price Variation and Collection Coverage

Ranks offers by their historical price range and reports how many offers and routes appear on each collection date.

## Results

Median prices by booking window, using the lowest recorded price per offer per collection date. Amounts are reported in CAD.

| Days Before Departure | Economy (Basic) | Economy | Economy (Premium) |
|---|---:|---:|---:|
| 31+ | 134 | 253 | 564 |
| 22–30 | 124 | 255 | 598 |
| 15–21 | 251 | 271 | 1,079 |
| 8–14 | 260 | 361 | 1,189 |
| 0–7 | 314 | 438 | 1,446 |

The lowest median Basic fare occurred in the 22–30 day window. Economy and Premium had their lowest median fares in the 31+ day window. All three categories had their highest median fares within seven days of departure.

Across **2,627 matched price comparisons**, increases were more frequent than decreases in every cabin category:

| Cabin Category | Increases | Decreases | Unchanged |
|---|---:|---:|---:|
| Economy (Basic) | 641 | 277 | 380 |
| Economy | 221 | 118 | 130 |
| Economy (Premium) | 384 | 106 | 370 |
