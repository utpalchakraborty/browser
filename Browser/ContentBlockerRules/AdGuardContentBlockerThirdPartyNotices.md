# Content-blocking data

The bundled `AdGuardBaseRules.json` and
`AdGuardTrackingProtectionRules.json` files were generated from the AdGuard
Base and AdGuard Tracking Protection filters.
The source filters are maintained by AdGuard Software Ltd. and contributors at
<https://github.com/AdguardTeam/AdguardFilters> under GPL-3.0-only.

The native WebKit JSON was generated offline with AdGuard Safari Converter
4.3.0 from <https://github.com/AdguardTeam/SafariConverterLib>, also licensed
under GPL-3.0-only. The converter is a developer tool and is not linked into or
shipped with Browser.

Exact source versions, hashes, converter inputs, and generated-output hashes
are recorded in `ContentBlockerManifest.json`. Browser performs no filter
download or update request at runtime.
