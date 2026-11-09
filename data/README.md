# Referral directory (`services.csv`)

Demo state: **Lagos**. Every row in the shipped file is a **placeholder** (`verified=false`).
The app labels unverified rows "DEMO DATA – not a real service" and shows them **only when
`DEMO_MODE=true`**. With `DEMO_MODE=false`, only rows with `verified=true` and a
`verified_at` date within `SERVICE_VERIFIED_MAX_AGE_DAYS` (default 90) are ever shown.

To add a real service, phone or visit it and record:

| column | meaning |
|---|---|
| `name`, `address`, `area` | as confirmed by the facility |
| `area_aliases` | `|`-separated neighbourhood names users might type |
| `days`, `hours` | opening times as confirmed |
| `is_free`, `youth_friendly`, `accepts_under_18` | `true`/`false`, confirmed with staff |
| `services` | `|`-separated: `hiv_test`, `prep`, `pep`, `sti`, `self_test` |
| `verified` | `true` only after confirmation |
| `verified_at`, `verified_by` | `YYYY-MM-DD`, initials of the person who checked |
| `maps_url` | optional directions link |

Never copy a facility from a web search without confirming it directly.
