# Governance

This document outlines the governance model for the Spectra project.

## Maintainers

- **Project Lead**: [@dsclca12](https://github.com/dsclca12) — overall direction and final decisions

## Decision Making

Major decisions about the project direction are made through discussion in GitHub Issues and Discussions. The project lead has final say, but consensus is preferred.

## Contribution Process

1. Discuss significant changes via GitHub Issues before implementation
2. Submit changes via Pull Request
3. At least one maintainer review required for merge
4. All commits must follow [Conventional Commits](https://www.conventionalcommits.org/)

## Subsystems

| Subsystem | Description | Tech Stack |
|-----------|-------------|------------|
| Core | Database, providers, state management | Dart, Drift, Riverpod |
| UI | Components, screens, layout | Flutter |
| Native | FFI bindings, image processing | C, ONNX Runtime |
| Platform | Windows integration | C++, Win32 API |

## Recognition

Contributors who make significant or repeated contributions may be invited to become maintainers.
