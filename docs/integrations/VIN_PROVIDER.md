# VIN provider

Release 1 uses a basic decoder adapter. The user types or pastes the VIN; camera scanning is excluded.

- Normalize and validate where applicable.
- Check workspace records before provider call.
- Save provider, timestamp, raw response, mapped fields, and error.
- Present mapped fields as suggestions.
- Allow authorized manual correction with provenance and audit.
- Provider failure does not prevent manual creation when required fields can be entered.

Future OCR/document extraction may propose VIN and cost from uploaded paperwork as a separate module.
