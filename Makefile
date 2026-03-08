# Devshell — SSH workspace container
IMAGE := ghcr.io/cameronsjo/devshell
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

.PHONY: help build run stop clean shell

.DEFAULT_GOAL := help

## Development ────────────────────────────────────────────

# Show available targets
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# Build the Docker image locally
build: ## Build devshell image
	docker build \
		--build-arg VERSION=$(VERSION) \
		--build-arg GIT_COMMIT=$(COMMIT) \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		-t $(IMAGE):$(VERSION) \
		-t $(IMAGE):latest \
		.

# Run devshell locally for testing (ephemeral home, no Docker socket)
run: ## Run devshell locally (test mode)
	docker run -d --name devshell-test \
		-p 2222:22 \
		-e PUID=$(shell id -u) \
		-e PGID=$(shell id -g) \
		$(IMAGE):latest

# Stop and remove test container
stop: ## Stop test container
	docker rm -f devshell-test 2>/dev/null || true

# Shell into running test container
shell: ## Shell into test container
	docker exec -it -u dev devshell-test zsh

## Cleanup ────────────────────────────────────────────────

# Remove built images and test containers
clean: stop ## Clean up images and containers
	docker rmi $(IMAGE):latest $(IMAGE):$(VERSION) 2>/dev/null || true
