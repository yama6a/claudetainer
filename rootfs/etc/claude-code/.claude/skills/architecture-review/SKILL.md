---
name: architecture-review
description: Whole-repo architecture and maintainability review, then the refactor that follows from it, in any language, with references for Go and for React with TypeScript. Use it when the user asks for an architecture review, a maintainability or code-quality review of a whole repo or service, a cleanup of folder structure or package layout, to "DRY up" or de-duplicate a codebase, to find repeating patterns, to rename unclear packages or types, to remove dead code, or to cut comments and docs that state the obvious. Also use it when a codebase grew fast, with many similar modules, integrations, handlers or pages, and the user wants it easier to read. Not for reviewing one diff for bugs (use code-review) or polishing one changed file (use simplify).
---

# Architecture review

Goal: a reader who has never seen the repo finds what is where fast, and reads code whose names make comments unnecessary. Maintainability beats line count, cleverness and completeness. Copied code is fine when it keeps a reader's path short.

The review has four phases. Each ends with something the owner can see.

1. Measure and scope.
2. Review in parallel, read-only.
3. Plan, and ask the owner the real decisions.
4. Refactor in small ordered PRs, verified one by one.

Before you start, read the repo's own rules: CLAUDE.md, README, contributing guide, lint config. Where they conflict with this skill, the repo's rules win, unless the owner approves an exception.

## Principles to judge against

- **Build for today's callers.** No extension point, option or hook for a case that does not exist yet.
- **An abstraction must pay for itself.** A wrapper or interface that only forwards calls goes.
- **One rule in one place.** Logic that appears a second time gets extracted. Do not re-check what a schema, spec or generated type already enforces.
- **Plain control flow.** A function and a switch beat closures, function tables and callbacks. Past four or five parameters, pass a struct or split.
- **Delete dead code.** That covers a function only tests call, a config field nothing sets, and plumbing for a feature with no implementation.
- **One field per fact.** Two fields that can say the same thing will one day disagree.
- **Count concepts, not lines.** A change that removes a concept a reader must hold beats one that removes lines.
- **Names over comments.** A comment explains a WHY the code cannot show. A comment that restates the code goes, and a better name replaces a comment that explains a name.

### When to extract a shared helper, and when not

Extract when the copies are identical or near-identical, and the helper's name says what it does. Keep the copies when:

- the shared version needs a callback, a lambda or a flag parameter to cover the differences. That hides per-case logic, and the reader now opens two places.
- the copies only look alike but follow different rules.
- there is one copy plus one planned use. Wait for the second real case.

A good shared helper takes data and returns data, such as `RateRamp{Start, Max, Gap}.Allow(history, now)`. A helper that takes a function to call back is usually the wrong cut.

## Phase 1: measure and scope

Before reviewers start, know the shape:

- the line count of production code without generated files and mocks, per top-level folder
- the directory tree two levels deep
- the docs that exist and their length

Name the repos in scope. A service and its frontend count as one review with separate reviewers.

## Phase 2: parallel read-only reviewers

Split the codebase into dimensions that do not overlap, and give each to its own subagent. A split that works well:

| Reviewer | Scope |
|---|---|
| Layout | folder structure, package or module boundaries and names, dependency direction, wiring and entry points, dead code, whether the docs' layout table matches |
| Repeated modules | groups of sibling modules that do the same job, such as integrations, plugins, provider clients or handlers: file layout, repeated code, contract coherence, naming, test scaffolding |
| Core code | services, data access, API handlers, domain types: repeated patterns, long or tangled functions, naming drift across layers, comments, error handling |
| Frontend | folder structure, repeated data loading, form and table patterns, large components, API client use, test fixtures, styling repetition |

Drop a row that does not apply, and split a row that is too big for one reader.

Give every reviewer the same brief shape:

- The goal and the principles above.
- Exactly which paths it owns, and which another reviewer covers.
- "Read-only. Do not edit, commit or run anything that writes."
- The questions to answer, numbered.
- The output: a prioritized list of at most 25 items. Each item names the what, the where (paths), the proposal (with a concrete name or signature for any new helper), the value, the effort (S/M/L) and the risk. A target tree when the layout should change.

Use the strongest model for these, because they need judgement. Run them in the background, so their file dumps stay out of the main context.

Keep each reviewer alive after it reports. The reviewer that found a problem implements its fix later, because it already holds the context.

What each reviewer looks for is in [references/checklist.md](references/checklist.md). For Go, also hand over [references/go.md](references/go.md). For React with TypeScript, hand over [references/frontend.md](references/frontend.md).

## Phase 3: plan and decide

Merge the reports into one plan:

1. Drop duplicates across reviewers, and keep the more concrete proposal.
2. Group the items into steps. A step is one PR that a reviewer can read in one sitting, or one mechanical PR of moves and renames.
3. Order the steps so they collide least:
   1. Layout and renames. They are mechanical and touch everything.
   2. Repeated modules, through shared helpers.
   3. Core code.
   4. Docs and the comment sweep, last, because they describe the final state.

   A frontend runs in parallel with the backend.
4. Show the owner the plan as a short table: step, repo, what changes, size.

Then ask the owner only what is theirs to decide. Ask through the question tool when one exists. Typical decisions:

- **Deleting planned features.** Dead code that exists for a plan in the TODO list.
- **Renaming public names.** API fields, endpoints, package names other repos import. Say what has to change together.
- **Behaviour changes hidden in a cleanup.** For example, two modules disagree on an error rule, so unifying them changes one of them.
- **Exceptions to the repo's own rules.** For example, moving per-package error values into one shared package.
- **A rule that moves.** For example, a data store writing an audit entry that the caller used to write.

For each option, say what it does, what it costs and what changes if it is picked. Do not ask about things with an obvious answer. Decide those yourself, and name the choice in the report.

## Phase 4: refactor in ordered PRs

- **Give each step to the reviewer that found it.** Resume the same agent with the owner's decisions, and tell it what changed on main since its review.
- **Use one checkout per parallel branch.** Two agents on one working tree overwrite each other. Use git worktrees, and delete them at the end.
- **A large step can fan out.** The implementing agent may split work by module group across its own helpers. It then reviews their output for consistency before it reports.
- **Behaviour stays the same,** except for the approved changes and bugs found on the way. The report names each bug fix.
- **Each step ends green:** the full local CI, the race or concurrency tests, staged files, then the PR.
- **Merge after the hosted CI passes,** then watch the deploy if main deploys.
- **Rebase the next branch on the merged main.** Conflicts tend to come from the same few files: wiring, docs and TODO lists. Let the agent that wrote the branch resolve them, with a precise list of what landed on main.

### Coordinated releases

A renamed API field breaks the other side until both deploy. Prepare the client PR against the new spec first. Merge the server PR, wait for its deploy, then merge the client PR.

Name the repository explicitly in each merge command, for example `gh pr merge 12 -R owner/repo`. If a directory change fails silently, the command still runs, but in the wrong repo.

## Pitfalls

- **A comment sweep removes contracts.** A name or signature cannot show which error a function returns, or what a field holds in each case. Keep those facts as one clause on the doc comment. To check whether one matters, search for callers that match the error.
- **Facts that move from comments into docs must land in the docs.** Spot-check that each moved fact exists in its new place.
- **Parallel branches claim the same IDs:** numbers in a decision list, migration numbers, doc anchors. Expect a renumber at merge, and tell each agent to take the next free number after main.
- **A CI step that regenerates code and diffs it fails on unstaged files.** Stage before you run the local CI.
- **Test helpers that share global state turn flaky** once tests run in parallel. A shared HTTP connection pool closed by another test's server is a common case. One shared test helper, with its own state per test, fixes every copy at once.
- **An agent's edits can be lost** when its run stops early. Check the working tree before you trust a report, then resume the agent with what you found.
- **Line count is a side effect, not the goal.** A step that adds a few lines but removes a concept is a good step.

## Report to the owner

After each merge, give one line per PR: what changed for a reader of the code, and anything that now behaves differently.

At the end, give:
- a table of all PRs
- the size before and after
- what you left as is on purpose
- any slip made on the way

Use short sentences, and end without a closing summary.
