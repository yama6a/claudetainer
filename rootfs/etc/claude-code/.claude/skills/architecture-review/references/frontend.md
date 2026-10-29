# Frontend reference (React with TypeScript)

## Layout

- **Folders follow the navigation,** so a reader goes from a URL to a folder:
  - `app/`: shell, session, layout
  - one folder per feature, such as `orders/`, `settings/` or `admin/`
  - `shared/`: hooks, components, formatting
- **`shared/` never imports from a feature folder.**
- **File names:**
  - Route components end in `Page`.
  - Each file exports one component, named like the file.
  - Small private helpers stay in their parent's file.
- **A page never imports from another page.** Move what both need into the feature folder or into `shared/`.
- **A file whose name differs from a sibling only in case** is a smell, for example `stats.ts` next to `Stats.tsx`.

## Repeated patterns and the hooks that remove them

- **Data loading:** `useLoad(load, deps)` returns `{data, failed, reload, setData}`. Pair it with `Loading` and `LoadFailed` components. A failed load must show something. A blank page after an error toast is a bug.
- **Button actions:** `useAction()` returns `{busy, run}`. It keeps one idempotency key per action until the action succeeds. A confirm button stays disabled until its promise settles, so a slow delete cannot be confirmed twice.
- **Forms:** `useFormSubmit(send)` takes care of:
  - preventDefault
  - reading the fields
  - the busy state
  - the idempotency key
  - resetting the form on success
- **Polling:**
  - one hook, whose callers pass a plain function
  - a page's polling state lives in one hook, such as `useOrder(id)`, not spread across children that pass data up through callbacks
- **Status rules:** one module with typed status sets, not string sets repeated in several components.
- **Markup:** small components replace repeated class strings: `Field`, `Select`, `FormButtons`, `DataTable`, `PageTitle`, `EmptyState` and `ExternalLink`. A class-strings module holds class strings only.
- **Tests:**
  - one fixtures module, for example `testOrder(change?)` and `listOf(...)`
  - one API base constant
  - timers reset in the global setup

## API layer

- **One client for every call.** It handles auth, errors, toasts and the idempotency header. Check that no component calls `fetch` itself.
- **Empty or unreadable bodies** must not throw past the client.
- **Renamed API fields** ship in one coordinated release with the backend, as described in SKILL.md.

## What to leave alone

- **Inline role checks,** such as `{canWrite && <button>}`, read fine. Do not wrap them.
- **Two small list editors with different rendering** do not need one shared component with render props.
