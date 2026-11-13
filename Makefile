# raysolve — common tasks. `make` (or `make help`) lists them.

.DEFAULT_GOAL := help
.PHONY: help build test test-native check fmt diff bench bench-vm stress demo clean

I := --index fixtures/ecosystem

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

build: ## The native binary, ./raysolve
	rm -f raysolve
	ray build --native --release -o raysolve src/main.ray

test: ## Tests on the VM
	ray test

test-native: ## The same tests as native binaries
	ray test --native

check: ## Type-check without running
	ray check

fmt: ## Format the sources
	ray fmt -w src/*.ray tests/*.ray

diff: build ## Same commands on the VM and the native binary, outputs compared
	./scripts/difftest.sh

bench: build ## Generated indexes, native
	./raysolve bench --packages 800

bench-vm: ## Generated indexes, on the VM
	ray run . bench --packages 800

stress: build ## Write a 600-package index to fixtures/stress/ and resolve it from disk
	rm -rf fixtures/stress
	./raysolve gen fixtures/stress --packages 600 --seed 4
	./raysolve resolve fixtures/stress/ray.toml --index fixtures/stress/index | head -5

demo: build ## The fixture projects: a lock, two conflicts, why, outdated
	./raysolve resolve fixtures/projects/app.toml $(I)
	-./raysolve resolve fixtures/projects/conflict.toml $(I)
	-./raysolve resolve fixtures/projects/deep.toml $(I) --tree
	./raysolve why net fixtures/projects/app.toml $(I)
	-./raysolve outdated fixtures/projects/app.toml $(I)

clean: ## Remove the binary and the generated index
	rm -f raysolve
	rm -rf fixtures/stress
