# Security Policy for TrevVM 🔒

## Overview 📊

TrevVM takes security seriously. We appreciate responsible reports that help us protect users, contributors, and the wider community.

If you believe you have found a security vulnerability, please report it privately rather than opening a public issue. Public disclosure before a fix is available may put users at unnecessary risk.

## Reporting a Vulnerability 🫪

Please use GitHub's private vulnerability reporting feature by selecting **Report a vulnerability** on the repository's **Security** tab. If private reporting is unavailable, contact the project maintainers privately through an official GitHub channel.

Please include as much of the following information as possible:

- A clear description of the vulnerability
- The affected TrevVM version, commit, or configuration
- Steps to reproduce the issue
- A proof of concept, if available and safe to share
- The potential security impact
- Any suggested mitigation or fix
- Your preferred name or handle for acknowledgment

Please do not include passwords, API keys, private data, or other sensitive information in your report.

### Please Do Not 🤥

- Open a public GitHub issue for an unpatched security vulnerability
- Publicly disclose the vulnerability before coordinating with the maintainers
- Access, modify, or delete data that does not belong to you
- Perform denial-of-service testing against users or public services
- Use the vulnerability to obtain personal benefit

## Response Timeline 😅

We aim to acknowledge security reports within **two business days**. After acknowledgment, we will investigate the report, assess its severity, and communicate next steps when possible.

Response time may vary depending on the complexity and severity of the issue. If you do not receive an acknowledgment within two business days, please send a polite follow-up through the same private channel.

## Security Advisory Process 🤗

Our general process is:

1. **Private report** — A researcher submits the report through a private channel.
2. **Acknowledgment** — The maintainers confirm receipt and request clarification if needed.
3. **Investigation** — We reproduce the issue and assess its scope and severity.
4. **Fix development** — We prepare, review, and test a patch or mitigation.
5. **Release** — We publish an updated version or mitigation guidance.
6. **Disclosure** — We may publish a security advisory after users have had a reasonable opportunity to update.

We may coordinate the disclosure date with the reporter. For severe issues, we may ask for a longer embargo; for issues that are already public, we will prioritize rapid communication and mitigation.

## Supported Versions ✅

Security fixes are generally prioritized for the latest development version and the latest stable release.

| Version | Support status |
| --- | --- |
| Latest release | Security fixes and updates |
| Development version (`main`) | Fixes as development continues |
| Older releases | Best effort; users should upgrade |

Because support can change as the project evolves, users should keep TrevVM updated and review release notes for important changes.

## Security Best Practices 🫠

### For Users 🤖

- Use the latest available TrevVM version.
- Download TrevVM only from trusted project sources.
- Verify release information before installing updates.
- Keep the host operating system and dependencies patched.
- Avoid running untrusted VM programs or input with unnecessary privileges.
- Do not expose sensitive credentials to VM programs or debugging tools.
- Review logs and unexpected behavior, and report suspicious findings privately.

### For Contributors 👁️

- Validate and safely handle untrusted input.
- Avoid committing secrets, credentials, or personal data.
- Keep dependencies up to date and review dependency changes.
- Add regression tests for security fixes where practical.
- Use code review for changes affecting execution, isolation, permissions, or parsing.
- Document security-relevant behavior and limitations.

## Community Discussions and Support 😊

GitHub Discussions and regular issues are appropriate for general questions, troubleshooting, feature requests, and non-sensitive bugs. Community members may be able to help with configuration and usage questions.

Do not post vulnerability details, exploit code, credentials, private logs, or other sensitive information in public discussions or issues.

## AI-Assisted Troubleshooting 👾

AI tools may help explain error messages, suggest debugging steps, or identify likely configuration problems. Before sharing information with an AI service, remove credentials, proprietary source code, personal data, and other sensitive material.

AI-generated advice should be reviewed and tested carefully. Do not rely on an AI tool as a substitute for privately reporting a suspected security vulnerability.

## Disclosure and Credit 📝

We ask reporters to allow reasonable time for investigation and remediation before public disclosure. We welcome coordinated disclosure and will work with reporters in good faith to establish an appropriate timeline.

With the reporter's permission, we may acknowledge their contribution in a security advisory or release notes. We will respect requests to remain anonymous.

## Scope 📍

This policy covers security vulnerabilities in TrevVM and its maintained source code. Reports about third-party dependencies may need to be submitted to the relevant upstream project as well; please mention such dependencies in your report so we can coordinate when appropriate.

Security reports should focus on reproducible issues that could affect confidentiality, integrity, availability, isolation, or the safe operation of TrevVM.

## Commitment 🤩

We are committed to responding respectfully, protecting good-faith reporters, and improving TrevVM's security over time. Thank you for helping make the project safer.

---

**Last updated:** 2026-10-22
