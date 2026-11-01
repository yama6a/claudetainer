# Review checklist

Language-neutral. Each reviewer takes the sections for its scope.

## Layout and boundaries

- **Findability:** can a reader tell from the tree alone where a feature lives?
  - Folder names say what is inside, not what kind of file it is.
  - `utils`, `helpers`, `common`, `misc` and `lib` are warning signs.
- **Grouping levels:** does every grouping level have a rule? A level such as `pkg/` or `shared/` with no stated rule for what belongs there is noise. Remove the level, or state the rule.
- **Name clashes:** do two names clash, or read as one topic? Examples:
  - `config` next to `configs`
  - a service and a data store with the same package name, so imports need aliases
- **One purpose per module:**
  - Does each module have one purpose you can state in one sentence without "and"?
  - Does its name state that purpose? A package named `publish` whose code does not publish misleads the reader.
- **Dependency direction:** domain types at the bottom, storage and services above, API and background workers on top. List the imports that point the wrong way, and anything placed oddly only to avoid an import cycle.
- **Wiring:** how many places must change to add one more module of a kind, such as one more integration or endpoint? The target is one block in one file.
- **Dead code:** unused packages, functions only tests call, config nothing reads, plumbing for an unbuilt feature. Use the language's dead-code tool where one exists.
- **Docs:** does the docs' layout table match the tree?

## Repeated modules

Put the sibling modules side by side.

- **File layout:** do the same concerns live in files with the same names? Propose one standard layout, and list the deviations.
- **Repeated code:** for each pattern, list:
  - which modules repeat it
  - how close the copies are: identical, near-identical or really different
  - whether a shared helper makes the code shorter and also easier to read

  Typical patterns:
  - auth and token flows
  - HTTP send with error classification
  - rate-limit and retry parsing
  - secret or config decoding
  - polling waits
  - throttling
  - media download
  - test servers and fixtures
- **Rules the caller could own:** for example, every module marks a failed login as final, when the caller could do it once.
- **The contract:**
  - Are the interfaces coherent and well named?
  - Are there too many optional ones?
  - Should any be data instead of an interface?
- **One concept, many names:** list them, and pick one name. Examples:
  - `findPost`, `recentDuplicate` and `findTopic` for one job
  - a parameter named `d` that should be `post`
- **Test scaffolding** copied per module: fake servers, request recorders, error-kind asserts.

## Core code

- **Repeated patterns:**
  - data access boilerplate: transaction plus audit plus scan
  - handler boilerplate: decode, access check, convert, write
  - conversion files
  - background job payload handling
  - status derivation

  For each, give how many copies exist, and the signature of a helper that removes them without hiding logic.
- **Long functions and files:** list the 15 longest or most branching, with path:line, and a split by responsibility for each.
- **A rule implemented twice:** for example, a status derived both in the store and in a worker, or a validation both in a generator and in a service. Keep one place, preferably a method on the domain type.
- **Business logic in the transport layer:** for example, HTTP handlers that decide more than whether the input is valid. Move it into a service.
- **Word drift across layers:** the same concept with different names in the API, the code and the database, for example `maxLength` and `MaxTextLength`. Use one word per concept, everywhere.
- **Untyped vocabularies:** audit actions, entity types, actor names and job kinds as string literals across many files. Make them typed constants.
- **Error handling:**
  - Keep one mapping from errors to API status, not a growing list of special cases from many packages.
  - Keep wrap wording and log keys consistent.

## Comments and docs

- **Comments that restate the code:** delete them.
- **Comments that explain a name:** rename, then delete the comment.
- **Comments that explain history,** such as "renamed from" or "previously": delete them. Git holds history.
- **Comments that stay:** a WHY the code cannot show. That means a workaround, a constraint you cannot see from the code, or a contract the signature cannot show, such as which errors a caller can match or what a field means in each case.
- **Interface docs** copied from the implementation drift. Keep the contract on the implementation. On the interface, keep only what its consumer relies on.
- **Each fact in one place.**
- **Long docs:** a doc that mixes a contract with many per-module sections splits into one page per module, plus an index.
- **Runbooks:** split them by task, such as install, connect and recover.
- **What docs cover:** decisions and architecture, not internals the code already shows.

## Frontend

See [frontend.md](frontend.md).
