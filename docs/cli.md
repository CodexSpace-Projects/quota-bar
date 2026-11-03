# CLI reference

The release ZIP includes a universal `quota-bar` binary for shell scripts, Shortcuts and local alerts.

## Status

```sh
quota-bar status [--json] [--threshold 0...100]
```

Text mode prints one line per rate-limit window plus the tightest remaining value. JSON mode returns a versioned object with ISO-8601 timestamps and never exposes raw app-server data.

Exit codes:

- `0`: current data returned and above the threshold, or no threshold was supplied.
- `1`: invalid arguments, unavailable Codex data or another operational error.
- `2`: current data returned and the tightest window is at or below the supplied threshold.

## Local history

```sh
quota-bar history [--json] [--days 1...90]
                    [--currency USD|AUD|EUR] [--exchange-rate N]
                    [--input-rate N] [--cached-input-rate N] [--output-rate N]
```

History attributes each positive token delta to the latest model ID recorded by the preceding local `turn_context`. Known models use the bundled official standard API price snapshot automatically. Rate flags are optional USD-per-million-token fallbacks for an unknown future model.

JSON history schema version 2 includes model usage, the price used, pricing status (`official`, `fallback`, or `unpriced`), the total API-equivalent estimate, catalogue date and official source URL.

USD is the default. AUD and EUR use the bundled 14 July 2026 ECB reference rates. `--exchange-rate` can override the number of selected-currency units per USD for scripts that supply a newer rate; it requires `--currency`. Custom unknown-model price flags are USD per million tokens before conversion.

The estimate is not ChatGPT subscription spend. Local aggregate records do not expose enough request-level detail to infer long-context, regional, priority, batch, flex, cache-write or tool-call adjustments.
