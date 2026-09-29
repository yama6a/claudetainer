GO_LINT_CONFIG     ?= .build/golangci.yaml
CANONICAL_LINT_URL := https://raw.githubusercontent.com/yama6a/gha/v2/.golangci.yaml
GOVULNCHECK_URL    := https://raw.githubusercontent.com/yama6a/gha/v2/scripts/govulncheck.sh
IMAGE              ?= claudetainer:dev

.PHONY: lint-config generate fmt fmt-check lint vet test cover vuln tidy tidy-check \
	generate-check mod image ci

lint-config:
	mkdir -p .build
	curl -fsSL $(CANONICAL_LINT_URL) -o .build/canonical-golangci.yaml
	if [ -f .golangci.local.yaml ]; then \
		yq eval-all '. as $$item ireduce ({}; . *+ $$item)' \
			.build/canonical-golangci.yaml .golangci.local.yaml > $(GO_LINT_CONFIG); \
	else \
		cp .build/canonical-golangci.yaml $(GO_LINT_CONFIG); \
	fi

generate:
	go generate ./...

fmt: lint-config
	golangci-lint fmt -c $(GO_LINT_CONFIG)

fmt-check: lint-config
	golangci-lint fmt --diff -c $(GO_LINT_CONFIG)

lint: lint-config
	golangci-lint run ./... -c $(GO_LINT_CONFIG)

vet:
	go vet ./...

test:
	go test ./... -race -count=1

cover:
	go test ./... -coverprofile=cover.out -covermode=atomic
	go tool cover -func=cover.out | tail -1

# The same wrapper CI runs, so a .govulncheck-ignore entry counts in both places.
vuln:
	mkdir -p .build
	curl -fsSL $(GOVULNCHECK_URL) -o .build/govulncheck.sh
	bash .build/govulncheck.sh

tidy:
	go mod tidy

tidy-check:
	go mod tidy
	git diff --exit-code -- go.mod go.sum

generate-check: generate
	git diff --exit-code

mod:
	go get -u -t ./...
	go mod tidy

image:
	docker buildx build -t $(IMAGE) --load .

ci: tidy-check generate-check fmt-check lint vet test vuln

# ---- claudetainer ----
SHELL_FILES := rootfs/usr/local/bin/claudetainer-start $(wildcard rootfs/usr/local/lib/claudetainer/*.sh) test/smoke.sh

.PHONY: lint-image smoke

# The same checks as CI's shell, yaml and hadolint steps. Needs shellcheck, shfmt, hadolint, yamllint, actionlint.
lint-image:
	shellcheck $(SHELL_FILES)
	shfmt -d -i 2 -ci -bn -sr $(SHELL_FILES)
	hadolint --ignore DL3008 --ignore DL3018 --ignore DL3006 --failure-threshold info Dockerfile
	yamllint -d '{extends: relaxed, rules: {line-length: disable, truthy: disable, colons: disable, empty-lines: disable}}' .github
	actionlint -ignore 'unknown permission scope "copilot-requests"' -ignore 'label ".+" is unknown' .github/workflows/*.yaml

smoke: image
	./test/smoke.sh $(IMAGE)
