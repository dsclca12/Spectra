.PHONY: all clean analyze test run build help

help: ## Show this help
	@echo "Spectra — Build & Development Commands"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: clean get analyze test build ## Clean, get deps, analyze, test, and build

get: ## Install dependencies
	flutter pub get

clean: ## Clean build artifacts
	flutter clean

analyze: ## Run dart analyzer
	dart analyze

test: ## Run all tests
	flutter test

test-coverage: ## Run tests with coverage
	flutter test --coverage

build-release: ## Build Windows release
	flutter build windows --release

build-debug: ## Build Windows debug
	flutter build windows --debug

run: ## Run the app
	flutter run -d windows

format: ## Format Dart code
	dart format lib/ test/

fix: ## Apply automated fixes
	dart fix --apply

outdated: ## Check outdated dependencies
	flutter pub outdated

upgrade: ## Upgrade dependencies
	flutter pub upgrade
