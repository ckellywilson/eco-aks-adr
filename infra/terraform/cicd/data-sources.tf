# Hub integration is OPTIONAL — empty values = bootstrap mode (no hub).
# Bootstrap: CI/CD deploys first with own DNS zones, no peering.
# Day 2: re-apply with hub values to add peering, custom DNS, hub DNS zones.
# Deployment order: CI/CD (bootstrap) → Hub → CI/CD (Day 2) → Spoke.
