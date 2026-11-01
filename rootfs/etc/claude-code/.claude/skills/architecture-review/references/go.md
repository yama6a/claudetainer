# Go reference

Hand this to every reviewer and implementer of a Go repo.

## Measure

```sh
find . -name '*.go' -not -name '*.gen.go' -not -path '*/mock/*' | xargs wc -l | tail -1
go list ./...                                        # package list
go run golang.org/x/tools/cmd/deadcode@latest ./...  # unreachable functions
```

## Layout

- **`cmd/<binary>/`:** wiring only: flags, config, constructors, the server. Split it by topic, such as `config.go`, `env.go` and `api.go`, not one large `wire.go`.
- **`internal/`:** everything that no other repo imports. Do not add an `internal/pkg/` level without a rule, because the level says nothing.
- **Package names:** name a package by what is inside. No `utils`, `helpers` or `common`.
- **Data access:** one package per aggregate is fine, with shared transaction helpers in the parent package.
- **Domain types:** in one `domain` package, split into one file per aggregate. Moving them next to their stores tends to create import cycles.
- **Background jobs:** keep the kinds next to their payload types. The kind follows from the payload type (`JobKind() JobKind`). One generic `DecodePayload[P]` does the decoding and fails at once on a bad payload.
- **Fakes:** test-only implementations sit next to the contract or in a `*test` package, not among the production siblings.

## Interfaces and dependencies

- **Small interfaces at the consumer.** The consumer declares the interface it needs, for example in a `deps.go`.
- **No lone interfaces.** No exported interface next to its only implementation, and no `Impl` suffix or `I` prefix.
- **Compile-time checks across packages** (`var _ X = (*other.Y)(nil)`) belong in a `_test.go` file. In production code, the check adds an import only for itself.
- **No forwarding wrappers.** A wrapper that only forwards calls goes.
- **Optional capabilities** as small interfaces found by type assertion are fine. Marker interfaces with an empty method are acceptable while there are one or two. Revisit them at the third.

## Repeated code: helper shapes that work

- **A rule as a value type with a method:** for example `RateRamp{Start, Max, Gap}.Allow(history, now)` for throttling.
- **One HTTP send:** it reads a bounded body and classifies transport errors. Add a `StatusError{Call, Status, Code, Message}` type and one status-to-kind function. Each module keeps its own special cases as the first cases of its own `classify`.
- **One OAuth2 token call** for exchange and refresh. A small app struct carries the real differences: basic auth or form fields, the client ID field name, a user agent. Authorize URLs and identity checks stay per module.
- **Small generic helpers:** `DecodeSecret[T]`, a cancellable `Sleep(ctx, d)`, and `slices.Chunk` for batching.
- **Data access:** `QueryOne[T](ctx, db, scan, query, args...)` and a guarded variant replace the "begin, query one, scan, map the error, commit" block.
- **HTTP handlers:** generic `get` and `remove` helpers for the plain cases only. Custom handlers stay explicit.
- **Derived state:** a method on the domain type, called inside the same transaction as the write that changes its inputs.

Avoid helpers that take callbacks to cover the differences between copies. In Go, a closure-heavy helper reads worse than three explicit copies.

## Errors

- **Sentinels:** declare them per package. Exception: when many sibling packages declare the same generic sentinels, and nothing matches them per package, move those few into the shared contract package.
- **Error to HTTP status:** map through a small set of category errors, such as `ErrInvalid` and `ErrUnavailable`, that the package sentinels wrap. Do not add one case per sentinel in the API layer.
- **Wrapping:** wrap once per layer, and only with context the caller lacks. Never write "failed to". Error messages are lowercase, with no trailing punctuation.
- **Matching:** inspect errors with `errors.Is` and `errors.As`. Never match error strings.

## Style that marks code as careless

- **Comments that narrate control flow,** and `// Package foo provides foo` boilerplate.
- **Defensive nil checks** inside a package where no caller can pass nil. Check only at trust boundaries.
- **Long names where Go uses short ones:**
  - Receivers get one or two letters, consistent per type.
  - Loop variables are `i`, `k` and `v`.
  - A context is always `ctx`.
- **Stutter,** as in `user.UserID`.
- **`Get` prefixes** on getters.
- **`(T, error)`** when the error is always nil. **`(nil, nil)`** returns.
- **`make([]T, 0)`** where `var x []T` does.
- **Factory functions** for trivial structs.
- **Getters and setters** on plain data structs.
- **Goroutines without a visible exit,** a context stored in a struct, and `context.TODO()` in committed code.
- **Package-level mutable state,** and `init()` with visible effects.

## Comments

- **Exported identifiers:** one sentence that starts with the name, because lint usually requires it. Make it say something the name does not.
- **What to keep:** the error values a caller matches, and what a field means in each case.
- **Trailing field comments,** such as `Email string // lowercase`, carry one fact more cheaply than a doc block.

## Tests

- **One shared fake-server helper.** It records requests, queues failures, finds requests by method and path, and gives a client with no retry waits. It replaces one hand-written fake per module.
- **No `http.DefaultTransport` in parallel tests.** `httptest.Server.Close` closes its idle connections, and that breaks other tests' requests. Give each test its own transport.
- **Table-driven tests** by default. `t.Helper()` in helpers.
- **No `time.Sleep` to wait for async work.**
- **No tests that only repeat compile-time checks.** Delete them.
- **Before each merge,** run `go test -race -count=3` on the touched packages.

## Lint

- **Every lint exception needs a reason.**
- **A complexity exception** on one flat registration list is fine. Splitting that list into arbitrary groups only to please the linter reads worse.
