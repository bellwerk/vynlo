# @vynlo/integrations

Provider-port ownership boundary for tenant-neutral external systems.

This package is an ownership boundary inside the modular monolith, not an
independently deployed service.

## VIN decoding

`NhtsaVpicVinDecoderAdapter` implements the `VinDecoderPort` against the
official NHTSA vPIC flat decode endpoint. The adapter normalizes a typed or
pasted 17-character VIN, bounds response size and time, blocks unsafe endpoint
configuration, retains the JSON response for the application snapshot, maps
provider values only as suggestions, and classifies retryable failure and rate
limits without logging response bodies. See the
[official vPIC vehicle API](https://vpic.nhtsa.dot.gov/api/Home/Index).

The adapter is infrastructure. Workspace-scoped request persistence,
idempotency, audit, retry jobs, and user acceptance or override of suggestions
remain application/database responsibilities.
