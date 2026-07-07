# Security Policy

## Reporting

If you find a security issue in FrameScript, please open a private report through GitHub Security Advisories for this repository instead of filing a public issue.

## Secrets

FrameScript does not store provider API keys in project files. Keys entered in Settings are saved in the macOS Keychain under the `FrameScript` service name and are read only when a configured AI provider is used.

Before publishing a release, run a local secret scan and make sure generated files such as `DerivedData/`, `.build/`, `.swiftpm/`, `.env*`, provisioning profiles, certificates, and repository dumps are not committed.
