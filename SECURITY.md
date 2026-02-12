# Security Policy

## Reporting Security Vulnerabilities

### Template Repository (This Repo)

If you discover a security vulnerability in this template:

**Please report it via GitHub Security Advisories:**

1. Go to the [Security tab](../../security)
2. Click "Report a vulnerability"
3. Provide detailed information about the vulnerability
4. We will respond within 48 hours

**Do NOT:**
- Open a public issue for security vulnerabilities
- Discuss vulnerabilities in public forums until fixed

### Generated Infrastructure Code (User Repos)

If you discover vulnerabilities in infrastructure code you generated using this template:
- **Your infrastructure, your responsibility** - This template doesn't contain infrastructure code
- Follow your organization's security procedures
- Report to your security team
- The template maintainers are not responsible for security issues in user-generated code

---

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| v1.x    | ✅ Yes            |
| < v1.0  | ❌ No             |

We support the latest major version. Users should keep their templates updated.

---

## Security Best Practices

### For Template Maintainers

- ✅ Never commit credentials or secrets
- ✅ Review all PRs for sensitive information
- ✅ Keep dependencies up to date
- ✅ Use Dependabot for automated updates
- ✅ Enable branch protection on main branch
- ✅ Require code reviews for all changes

### For Template Users

After using this template to create your infrastructure repository:

#### Secrets Management
- ✅ Store secrets in Azure Key Vault, not in code
- ✅ Use Managed Identities for Azure authentication
- ✅ Never commit `*.tfstate` files (contains infrastructure state)
- ✅ Never commit variable files with sensitive values
- ✅ Use `.gitignore` to prevent accidental commits
- ✅ Enable secret scanning in your repository

#### Access Control
- ✅ Use Azure RBAC with least privilege principle
- ✅ Enable MFA for Azure accounts
- ✅ Use service principals for CI/CD pipelines
- ✅ Rotate credentials regularly
- ✅ Enable branch protection on main branch
- ✅ Require PR reviews for infrastructure changes

#### Network Security
- ✅ Use private endpoints for Azure services
- ✅ Implement network segmentation
- ✅ Enable network security groups (NSGs)
- ✅ Use Azure Firewall for egress control
- ✅ Enable DDoS Protection for production
- ✅ Enable NSG flow logs for monitoring

#### AKS Security
- ✅ Use private AKS clusters for production
- ✅ Enable Microsoft Defender for Containers
- ✅ Implement pod security standards
- ✅ Use Azure Policy for governance
- ✅ Enable audit logging
- ✅ Regularly update Kubernetes versions
- ✅ Use network policies (e.g., Cilium, Calico)

#### Monitoring
- ✅ Enable Azure Monitor for containers
- ✅ Configure log analytics
- ✅ Set up security alerts
- ✅ Monitor for suspicious activity
- ✅ Enable Microsoft Defender for Cloud

---

## Common Security Issues

### Issue: Terraform State Contains Secrets

**Problem:** Terraform state files may contain sensitive information.

**Solution:**
- Use remote state with encryption (Azure Storage, Terraform Cloud)
- Enable state file encryption
- Restrict access to state files
- Never commit state files to version control

### Issue: Hardcoded Credentials

**Problem:** Passwords or keys hardcoded in configuration files.

**Solution:**
- Use Azure Key Vault for secrets
- Use data sources to fetch secrets at runtime
- Use environment variables for sensitive data
- Enable secret scanning in your repository

### Issue: Overly Permissive Network Rules

**Problem:** Network Security Groups allow broad access.

**Solution:**
- Follow least privilege principle
- Implement network segmentation
- Use private endpoints where possible
- Regular security reviews

---

## Vulnerability Disclosure Timeline

1. **Report received** - Acknowledged within 48 hours
2. **Initial assessment** - Within 5 business days
3. **Fix development** - Based on severity
   - Critical: 1-7 days
   - High: 7-14 days
   - Medium: 14-30 days
   - Low: 30-90 days
4. **Release** - Fix included in next release
5. **Public disclosure** - 30 days after fix release

---

## Security Updates

**Stay Updated:**
- Watch this repository for security advisories
- Enable Dependabot for automatic dependency updates
- Review security best practices regularly
- Follow Azure security announcements

---

## Related Security Resources

### Microsoft Security Documentation
- [AKS Security Best Practices](https://learn.microsoft.com/azure/aks/operator-best-practices-cluster-security)
- [Azure Security Baseline for AKS](https://learn.microsoft.com/security/benchmark/azure/baselines/aks-security-baseline)
- [Container Security in Azure](https://learn.microsoft.com/azure/container-instances/container-instances-image-security)

### Azure Services
- [Microsoft Defender for Containers](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-containers-introduction)
- [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/)
- [Azure Private Link](https://learn.microsoft.com/azure/private-link/)

### Compliance
- [Azure Compliance](https://learn.microsoft.com/azure/compliance/)
- [AKS and Compliance](https://learn.microsoft.com/azure/aks/concepts-security#compliance)

---

## Contact

- **Security Issues**: Use GitHub Security Advisories (see above)
- **General Questions**: Open a GitHub issue
- **Urgent Security Matters**: Contact repository maintainers directly

---

**Thank you for helping keep this template and the infrastructure it generates secure!**
