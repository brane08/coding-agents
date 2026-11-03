# Money and multi-country rules for PostgreSQL apps

Covers: how to store and compute money, time, tax and effective-dated data so one schema serves several countries. Digest of a user-supplied guideline (PG 16+); applied partly in two repos (minor-unit money, tax bands, store-zone dates), the rest is design input. Not legal advice; verify per-country tax rules locally.

## Money
- Amounts are `bigint` minor units (+ ISO 4217 `currency_code` when multi-currency); never `float`, `double`, `BigDecimal` for stored amounts, or PG `money`.
- Exponent comes from config/currency table (`minor_unit`: JPY 0, USD 2, KWD 3); never hardcode `2` or `/100`, nor a `static final` parsed amount.
- One conversion class (`parse`/`format`/`ofMajor`/`percentOf`/`mulRound`), HALF_UP; `parse` strict and non-negative, `format` handles negatives. Load the exponent at startup and when setup changes it.
- Round once at the end; `numeric`/`BigDecimal` only for rates, weights and intermediates.
- Rates as basis points (1500 = 15%) only where documented per column; fixed discounts stay minor units; plain-percent config keys are not bp.
- Spread order-level discounts/fees/refunds over lines by largest remainder so parts sum exactly; store the per-line result.
- Cash rounding increment per country; record the adjustment on the payment.
- REST in/out money is integer minor units; JS clients must not use `Number()` on driver bigint/numeric or `parseFloat(x)*100`.
- Loyalty/points: floor once from minor units.

## Tax
- Rules as data: jurisdiction x category x component -> rate, effective-dated. Support tax-inclusive and exclusive pricing (flag on the order).
- Compute per line; snapshot rate, taxable amount and tax per line; history never re-reads the rate table.
- Credit notes/refunds instead of editing issued invoices.

## Time
- Instants as `timestamptz` (UTC). Business dates (school days, delivery slots, due dates, promotions) are local `date` in the store/school IANA zone; snapshot the zone on the order; never session `current_date`.
- Slot times as smallint minutes-of-day (`end_min` 1440 = midnight) rather than `time` when the ORM shifts `time` by the JDBC zone. Test DST gaps/overlaps.

## Effective dating
- Prices, promotions, tax bands: `tstzrange`/`daterange` + `EXCLUDE USING gist` (needs `btree_gist`); `COALESCE` nullable key columns. A change closes the old range and inserts a new row in one transaction; never update in place.

## Orders and inventory
- Completed orders are immutable snapshots (description, GTIN, unit price, discounts, taxes); corrections are refunds/adjustments.
- Weighed items: ordered vs picked quantity, authorise above estimate, capture actual.
- Gap-free document numbers: locked counter per legal entity + series, issued as late as possible.
- Inventory as append-only ledger (app role SELECT/INSERT), balance derived; lot code + best-before for recalls.

## Catalog, ids, text
- GTIN stored 14-digit zero-padded, GS1 check digit validated in DB; SKU/product/pack hierarchy; UN/CEFACT Rec 20 unit codes with exact `numeric` factors.
- `bigint` identity PK + `public_id uuid` for customer-facing entities; natural/national ids never PK (identifier-type + per-entity identifier tables; flag sensitive ones, encrypt at app level).
- Names: `full_name` required, given/family optional; no concatenation. Labels as jsonb `{"en":..,"xx-YY":..}` with a fallback chain.
- ICU collations, UTF-8 DB; nondeterministic collations do not support LIKE before PG 18: use FTS/`pg_trgm`.

## Tenancy, privacy, volume
- `tenant_id` on every tenant table, composite `(tenant_id,id)` FKs, RLS enabled + forced, non-owner app role without BYPASSRLS, `set_config('app.tenant_id', ..., true)` per transaction, views `security_invoker = true`. Global reference data has no tenant_id and is read-only to the app.
- Consent per purpose/policy version; tokenised payments only; age-restriction rules as data; audit log redacts sensitive columns; soft delete (`deleted_at`, partial unique indexes) is not erasure: erasure = anonymise + redact snapshots, keep financial rows.
- High volume: monthly range partitions, partition key in every PK, children carry parent `created_at`, no DEFAULT partition.
- Versioned report definitions + stored jsonb payload of what was submitted.

## Don't
- No `if country = ...` branches: per-country behaviour lives in tables/config.
