# @vynlo/design-tokens

Framework-neutral design-token ownership boundary.

This package is an ownership boundary inside the modular monolith, not an
independently deployed service. Milestone 1 exposes framework-neutral color,
typography, motion, focus, spacing, and touch-target contracts. Web CSS may
bind these values to custom properties; future native clients share the token
semantics, not React DOM components.
