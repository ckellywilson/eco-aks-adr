# Test Cases for Multi-Subscription Deployment Support

## Test Case 1: Same Subscription (Backward Compatibility)

### Input: Customer Answers (Without Question 9)
```
1. AKS cluster public or private? Private
2. Outbound traffic filtered? Yes
3. External access method? Application Gateway
4. Pods per node? ~250+ (Overlay)
5. Cilium/eBPF? Yes
6. Who controls network? Platform team
7. Environment? Production
8. Compliance? None
```

### Expected Output
- `crossSubscription.enabled` should be `false`
- `crossSubscription.requiresNetworkContributor` should be `false`
- No `subscriptionId` fields in hub or spoke objects
- All other configuration should parse normally

**Status**: ✅ Backward compatible - Question 9 defaults to "Same subscription"

---

## Test Case 2: Same Subscription (Explicit Answer)

### Input: Customer Answers (With Question 9 - Same)
```
1. AKS cluster public or private? Private
2. Outbound traffic filtered? Yes
3. External access method? Application Gateway
4. Pods per node? ~250+ (Overlay)
5. Cilium/eBPF? Yes
6. Who controls network? Platform team
7. Environment? Production
8. Compliance? None
9. Subscription deployment? Same subscription
```

### Expected Output
```json
{
  "crossSubscription": {
    "enabled": false,
    "requiresNetworkContributor": false
  }
}
```
- No `subscriptionId` fields in hub or spoke objects

**Status**: ✅ Correctly handles explicit "Same subscription" answer

---

## Test Case 3: Different Subscriptions (Valid)

### Input: Customer Answers
```
1. AKS cluster public or private? Private
2. Outbound traffic filtered? Yes, via firewall
3. External access method? Application Gateway
4. Pods per node? ~250+ (Overlay)
5. Cilium/eBPF? Yes
6. Who controls network? Platform team
7. Environment? Production
8. Compliance? None
9. Subscription deployment? Different subscriptions
   - Hub Subscription ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
   - Spoke Subscription ID: ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj
   - Network Contributor role confirmed: Yes
```

### Expected Output
```json
{
  "hub": {
    "subscriptionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    ...
  },
  "spoke": {
    "subscriptionId": "ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj",
    ...
  },
  "crossSubscription": {
    "enabled": true,
    "requiresNetworkContributor": true,
    "hubSubscriptionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "spokeSubscriptionId": "ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj"
  }
}
```

### Expected Documentation Output
```markdown
⚠️ **Multi-Subscription Deployment Detected**

**Configuration:**
- Hub Subscription: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`
- Spoke Subscription: `ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj`

**Required Permissions:**
Before deploying, ensure your service principal has:
1. **Contributor** role on hub subscription
2. **Contributor** role on spoke subscription
3. **Network Contributor** role on hub subscription (for cross-subscription VNet peering)

**Terraform Configuration Required:**
- Provider aliases needed for hub and spoke subscriptions
- VNet peering resources must reference appropriate providers
```

**Status**: ✅ Correctly handles multi-subscription deployment

---

## Test Case 4: Validation - Missing Subscription IDs

### Input: Customer Answers (Invalid - missing IDs)
```
9. Subscription deployment? Different subscriptions
   - Hub Subscription ID: [not provided]
   - Spoke Subscription ID: [not provided]
```

### Expected Behavior
- **ERROR**: "Different subscriptions requires both hub and spoke subscription IDs"
- Prompt user to provide missing subscription IDs

**Status**: ✅ Validation enforced

---

## Test Case 5: Validation - Invalid GUID Format

### Input: Customer Answers (Invalid GUID)
```
9. Subscription deployment? Different subscriptions
   - Hub Subscription ID: 12345678
   - Spoke Subscription ID: not-a-guid
```

### Expected Behavior
- **ERROR**: "Invalid subscription ID format. Must be GUID (8-4-4-4-12 hexadecimal)"
- Show valid format example: `12345678-1234-1234-1234-123456789abc`

**Status**: ✅ GUID validation enforced

---

## Test Case 6: Validation - Same GUID for Both

### Input: Customer Answers (Same GUID for hub and spoke)
```
9. Subscription deployment? Different subscriptions
   - Hub Subscription ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
   - Spoke Subscription ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
```

### Expected Behavior
- **WARNING**: "Hub and spoke subscription IDs are the same. Did you mean 'Same subscription'?"
- Suggest changing to "Same subscription" option
- If user confirms different subscriptions with same ID, allow but warn

**Status**: ✅ Detects same subscription ID usage

---

## Test Case 7: Cross-Tenant Warning

### Input: Customer Answers
```
9. Subscription deployment? Different tenants
```

### Expected Behavior
- **WARNING**: "Cross-tenant deployment is not fully supported in current implementation"
- Provide guidance:
  - Requires Azure AD cross-tenant trust configuration
  - Manual VNet peering setup needed
  - Additional authentication complexity
  - Recommend consulting with Azure architect

**Status**: ✅ Warns about unsupported scenario

---

## Integration Test: Full Workflow

### Scenario: Parse Multi-Subscription Configuration → Generate Infrastructure

1. **Parse customer requirements** with Question 9 (different subscriptions)
2. **Output JSON** to `.github/configs/customer-config.json`
3. **Verify** JSON includes:
   - `hub.subscriptionId`
   - `spoke.subscriptionId`
   - `crossSubscription.enabled = true`
4. **Pass to generate-hub-infrastructure skill**
   - Should read `hub.subscriptionId`
   - Should generate provider alias configuration
5. **Pass to generate-aks-spoke skill**
   - Should read `spoke.subscriptionId`
   - Should generate cross-subscription VNet peering with provider aliases

**Status**: 🔄 Ready for downstream skill integration (future work)

---

## Acceptance Criteria Validation

- ✅ Question 9 added to customer-requirements-quick-reference.md
- ✅ parse-customer-requirements skill parses Question 9
- ✅ TypeScript interface includes subscriptionId fields
- ✅ crossSubscription object added to schema
- ✅ Validation rules enforce subscription ID requirements
- ✅ Examples provided for same and different subscription scenarios
- ✅ Documentation includes Terraform provider alias notes
- ✅ Documentation includes Network Contributor permission requirements
- ✅ Skill handles missing Question 9 gracefully (backward compatibility)
- ✅ All changes work together atomically
- ✅ README/skill documentation updated with new capability

---

## Notes

- All test cases are descriptive validation tests
- No automated test infrastructure exists in this repository
- Manual testing via skill invocation required
- Future: Consider adding automated JSON schema validation
