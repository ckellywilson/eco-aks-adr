# Hub integration is optional — values come from variables (not remote state).
# During bootstrap (no hub deployed), defaults apply: no peering, no custom DNS.
# After hub deploys, update prod.tfvars with hub values and re-apply.
#
# This eliminates the hard dependency on hub remote state, enabling CI/CD
# to deploy before the hub exists (bootstrap-first pattern).
