/*
 * fuel_layout.h — pure string/format helpers for the fuel estimate screen.
 *
 * Format choices:
 *   - Consumption in mL/km (matches the wire format directly).
 *   - Fuel remaining in litres with one decimal place (mL ÷ 1000).
 *   - Unknown values (0xFFFF) render as "-- KM", "-- ML/KM", "-- L".
 */
#ifndef HOST_SIM_FUEL_LAYOUT_H
#define HOST_SIM_FUEL_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

/* Sentinel for unknown uint16 fields on the wire. */
#define FUEL_UNKNOWN_U16 ((uint16_t)0xFFFFU)

/*
 * Format tank percentage: "73%" / "0%" / "100%".
 * buf_len must be at least 5 (3 digits + '%' + terminator).
 */
void format_tank_percent(uint8_t pct, char *buf, size_t buf_len);

/*
 * Format estimated range: "175 KM" / "-- KM".
 * buf_len must be at least 10.
 */
void format_range(uint16_t km, char *buf, size_t buf_len);

/*
 * Format consumption: "38 ML/KM" / "-- ML/KM".
 * buf_len must be at least 12.
 */
void format_consumption(uint16_t ml_per_km, char *buf, size_t buf_len);

/*
 * Format fuel remaining: "6.5 L" / "-- L".
 * Converts mL to L with one decimal place.
 * buf_len must be at least 10.
 */
void format_fuel_remaining(uint16_t ml, char *buf, size_t buf_len);

/*
 * Compute the pixel height of the filled portion of a vertical fuel bar.
 * Returns 0..bar_height, linearly scaled by pct (0..100).
 */
int fuel_bar_fill(uint8_t pct, int bar_height);

#endif /* HOST_SIM_FUEL_LAYOUT_H */
