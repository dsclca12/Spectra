# Contributing to Spectra

🎉 Thank you for considering contributing to Spectra! We welcome contributions of all kinds — bug reports, feature requests, documentation improvements, and code changes.

## Quick Links

- 📖 **Full Contributing Guide**: [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
- 🐛 **Report a Bug**: [Open a Bug Report](https://github.com/dsclca12/Spectra/issues/new?labels=bug&template=bug_report.md)
- 💡 **Request a Feature**: [Open a Feature Request](https://github.com/dsclca12/Spectra/issues/new?labels=enhancement&template=feature_request.md)
- 📋 **Code of Conduct**: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

## Quick Start for Contributors

```powershell
# Fork the repository, then clone your fork
git clone https://github.com/YOUR_USERNAME/Spectra.git
cd spectra

# Add upstream remote
git remote add upstream https://github.com/dsclca12/Spectra.git

# Create a feature branch
git checkout -b feat/your-feature-name

# After making changes, run checks
flutter pub get
dart analyze
flutter test

# Commit using conventional commits
git commit -m "feat(scope): brief description"
```

> For detailed instructions on coding standards, commit conventions, and development environment setup, please see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
