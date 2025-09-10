# AgentVerse Security Guide

## 🔐 API Key Management

### Critical Security Rules

**NEVER COMMIT API KEYS TO VERSION CONTROL**
- API keys provide access to paid services and sensitive data
- Committed keys are visible to anyone with repository access
- Keys in git history remain even after deletion

### Supported API Keys

| Service | Environment Variable | Where to Get |
|---------|---------------------|--------------|
| **Hugging Face** | `HF_TOKEN` | https://huggingface.co/settings/tokens |
| **Google Gemini** | `GEMINI_API_KEY` | https://aistudio.google.com/app/apikey |
| **OpenAI** | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| **Anthropic** | `ANTHROPIC_API_KEY` | https://console.anthropic.com/ |

### Secure Setup Process

1. **Run the secure setup script:**
   ```bash
   make setup-keys
   ```

2. **Verify your configuration:**
   ```bash
   make audit
   ```

3. **Check file permissions:**
   ```bash
   ls -la .env
   # Should show: -rw------- (600 permissions)
   ```

## 🛡️ Security Best Practices

### File Permissions

- `.env` files: `600` (owner read/write only)
- API key files: `600` (owner read/write only)  
- Scripts: `755` (executable by owner, readable by others)

### Git Security

The `.gitignore` file protects against committing:
- `.env` files
- Any file containing `*token*`, `*key*`, `*secret*`
- Service account JSON files
- Hugging Face and Gemini specific patterns

### Environment Variables

Never use API keys directly in code:

```bash
# ❌ BAD - Hardcoded in script
GEMINI_API_KEY="actual-key-here"

# ✅ GOOD - From environment
GEMINI_API_KEY=${GEMINI_API_KEY:-""}
```

### Docker Security

API keys in containers:

```dockerfile
# ❌ BAD - Keys in image
ENV GEMINI_API_KEY=actual-key-here

# ✅ GOOD - Runtime secrets
ENV GEMINI_API_KEY=""
# Pass at runtime: docker run -e GEMINI_API_KEY="$GEMINI_API_KEY"
```

## 🔍 Security Auditing

### Automated Checks

Run security audits regularly:

```bash
make audit          # Full security audit
make check-secrets  # Check for exposed secrets
```

### Manual Security Review

1. **Check git history for secrets:**
   ```bash
   git log --all --full-history -- "*token*" "*key*" "*secret*"
   ```

2. **Verify .gitignore coverage:**
   ```bash
   git check-ignore .env
   # Should output: .env
   ```

3. **Check file permissions:**
   ```bash
   find . -name "*.env" -o -name "*token*" -o -name "*key*" | xargs ls -la
   ```

### Secret Scanning

For additional protection, consider:
- [GitGuardian](https://gitguardian.com/) - Automated secret scanning
- [TruffleHog](https://github.com/trufflesecurity/trufflehog) - Find secrets in git history
- [Secretlint](https://github.com/secretlint/secretlint) - Lint for secrets

## 🚨 Incident Response

### If API Keys Are Compromised

1. **Immediately revoke the exposed keys:**
   - Hugging Face: https://huggingface.co/settings/tokens
   - Google: https://aistudio.google.com/app/apikey  
   - OpenAI: https://platform.openai.com/api-keys

2. **Generate new keys**

3. **Update your `.env` file:**
   ```bash
   make setup-keys
   ```

4. **Check for unauthorized usage:**
   - Review API usage dashboards
   - Check for unusual activity
   - Monitor billing/credits

### Cleaning Git History

If secrets were committed:

```bash
# Remove specific file from all history (DANGEROUS)
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch path/to/secret/file' \
  --prune-empty --tag-name-filter cat -- --all

# Force push (if using fork)
git push fork --force --all
```

## 🔧 Service-Specific Security

### Hugging Face
- Use read-only tokens when possible
- Scope tokens to specific repositories
- Regularly rotate tokens (every 90 days)

### Google Gemini
- Enable API key restrictions (IP, referer)
- Monitor usage in Google Cloud Console
- Use least-privilege service accounts

### Google Cloud
- Use service account keys instead of user credentials
- Rotate service account keys regularly
- Enable audit logging

## 📋 Security Checklist

- [ ] `.env` file has 600 permissions
- [ ] `.env` is listed in `.gitignore`
- [ ] No API keys in source code
- [ ] No API keys in Docker images
- [ ] Regular security audits (`make audit`)
- [ ] API key rotation schedule
- [ ] Monitoring for unusual API usage
- [ ] Incident response plan documented

## 🔗 Additional Resources

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [12-Factor App Config](https://12factor.net/config)

---

**Remember: Security is not optional. Protect your API keys like you would protect your passwords.**