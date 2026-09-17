# Agent-Friendly Docs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let an AI agent read the whole ReactiveComponent manual from one URL, or from the installed gem, without scraping the docs site.

**Architecture:** The docs site is Astro Starlight built from Markdown in `docs/src/content/docs`. A Starlight plugin emits `llms.txt` (index) and `llms-full.txt` (every page concatenated) at build time, so nothing is hand-maintained. The same Markdown files are added to the gemspec so they ship inside the gem. A short `AGENTS.md` at the repo root lists the rules agents get wrong without reading everything and points at both sources.

**Tech Stack:** Astro Starlight 0.38, `starlight-llms-txt` plugin, RubyGems gemspec, GitHub Pages deploy already in `.github/workflows/docs.yml`.

**Conventions for every commit:** headline under 50 chars, imperative, no prefix, no body unless there is a non-obvious why, no tool attribution trailers. One task = one commit. Do not commit `.commitflow/`.

---

### Task 1: Generate llms.txt from the docs build

**Files:**
- Modify: `docs/package.json` (dependency added by npm)
- Modify: `docs/package-lock.json` (by npm)
- Modify: `docs/astro.config.mjs:1-30`

**Step 1: Install the plugin**

Run:
```bash
cd docs && npm install starlight-llms-txt
```
Expected: `docs/package.json` gains `"starlight-llms-txt"` under dependencies. If npm cannot find the package, stop and report; do not substitute another plugin.

**Step 2: Register it in the Starlight config**

In `docs/astro.config.mjs`, add the import after the starlight import and a `plugins` key inside the `starlight({ ... })` options, next to `title`:

```js
import starlightLlmsTxt from 'starlight-llms-txt';
```

```js
    starlight({
      title: 'ReactiveComponent',
      plugins: [
        starlightLlmsTxt({
          projectName: 'ReactiveComponent',
          description:
            'Reactive server-rendered ViewComponents for Rails via ActionCable. ERB templates compile to JS at boot; components re-render on the client when data changes.',
        }),
      ],
```

If the build fails on an unknown option, remove `projectName` and `description` and retry with `starlightLlmsTxt()` alone. Check the plugin README in `docs/node_modules/starlight-llms-txt/README.md` for the option names.

**Step 3: Build and verify the files exist**

Run:
```bash
cd docs && npx astro build 2>&1 | tail -3 && ls dist/llms*.txt && grep -c "Derived Entities" dist/llms-full.txt
```
Expected: build succeeds, `dist/llms.txt` and `dist/llms-full.txt` listed, grep count of at least 1.

**Step 4: Check the index links carry the site base**

Run:
```bash
grep -m3 "reactive_component/" docs/dist/llms.txt
```
Expected: links look like `https://lluzak.github.io/reactive_component/dsl-reference/`. If they lack the `/reactive_component` base, the file is broken for agents; read the plugin README for a base or site option before continuing.

**Step 5: Commit**

```bash
git add docs/package.json docs/package-lock.json docs/astro.config.mjs
git commit -m "Generate llms.txt from the docs build"
```

---

### Task 2: Link the agent files from the README

**Files:**
- Modify: `README.md:12` (the Documentation | Quick Start | DSL Reference line)

**Step 1: Extend the links line**

Replace line 12 of `README.md`:

```markdown
**[Documentation](https://lluzak.github.io/reactive_component/)** | **[Quick Start](https://lluzak.github.io/reactive_component/quick-start.html)** | **[DSL Reference](https://lluzak.github.io/reactive_component/dsl-reference.html)** | **[llms-full.txt](https://lluzak.github.io/reactive_component/llms-full.txt)** for AI agents
```

**Step 2: Verify**

Run:
```bash
grep -c "llms-full.txt" README.md
```
Expected: `1`

**Step 3: Commit**

```bash
git add README.md
git commit -m "Link llms-full.txt from the README"
```

---

### Task 3: Ship the Markdown guides inside the gem

**Files:**
- Modify: `reactive_component.gemspec:26-28`
- Modify: `README.md` (Development section, line ~97)

**Step 1: Confirm the guides are not in the gem today**

Run:
```bash
ruby -e 'puts Gem::Specification.load("reactive_component.gemspec").files.grep(/docs/).size'
```
Expected: `0`

**Step 2: Add the docs glob to the gemspec**

Replace the `spec.files` block:

```ruby
  spec.files = Dir.chdir(__dir__) do
    Dir['{app,config,lib}/**/*', 'docs/src/content/docs/*.md', 'CHANGELOG.md', 'LICENSE.txt'].reject { |f| File.directory?(f) }
  end
```

Only `*.md`. The `index.mdx` landing page is site chrome and stays out.

**Step 3: Verify the guides are picked up**

Run:
```bash
ruby -e 'puts Gem::Specification.load("reactive_component.gemspec").files.grep(/docs/)'
```
Expected: the eight guide files, including `docs/src/content/docs/derived-entities.md`, and no `index.mdx`.

**Step 4: Build the gem and inspect it**

Run:
```bash
gem build reactive_component.gemspec 2>&1 | grep File && tar -xOf reactive_component-*.gem data.tar.gz | tar -tz | grep -c "docs/src/content/docs/.*\.md$"; rm -f reactive_component-*.gem
```
Expected: gem builds, count of `8`.

**Step 5: Tell readers where the guides live**

In `README.md`, under `## Development`, add one line before the code block:

```markdown
The guides in `docs/src/content/docs` ship inside the gem, so `bundle open reactive_component` gives you the full manual offline.
```

**Step 6: Rubocop**

Run:
```bash
bundle exec rubocop reactive_component.gemspec
```
Expected: `no offenses detected`

**Step 7: Commit**

```bash
git add reactive_component.gemspec README.md
git commit -m "Ship the Markdown guides inside the gem"
```

---

### Task 4: Add AGENTS.md with the rules agents get wrong

**Files:**
- Create: `AGENTS.md`
- Modify: `README.md:12` (append one more link)

**Step 1: Write the file**

Create `AGENTS.md`:

```markdown
# ReactiveComponent for AI agents

Full manual, one file: https://lluzak.github.io/reactive_component/llms-full.txt
Page index: https://lluzak.github.io/reactive_component/llms.txt
Offline: the same guides ship in the gem under `docs/src/content/docs/`.

## Rules that are not obvious from the DSL

- A template expression must return a primitive (String, Integer, Float, true/false, nil, Symbol, or Array/Hash of those). `<%= @order %>` raises `UnsafeBroadcastValueError`; write `<%= @order.status %>`. Dates need a formatter in the template.
- Templates compile on first render, not at boot and not in the browser. Anything the compiler cannot make reactive raises `CompileError` naming the source. Fix the ERB; do not catch it.
- A model only broadcasts if a component that `subscribes_to` it has been loaded. Production needs eager loading. In a console or a job, reference the component class before mutating the record.
- The wrapper id is prefixed with the component name: `message_row_message_5`, never the bare `dom_id`. Two components on one record never share an id.
- `live_action` params are filtered with `permit`, so declare every key: `live_action :move, params: [:label_id]`.
- Prefer `broadcasts stream: ->(record) { [record.owner, :things] }` over the default record stream when several components share a page.
- A derived entity (`include ReactiveComponent::Entity`) is keyed on one root record via `root :order` and declares its sources with `rebuilds_on Model, via: :order_id, fields: %i[...]`. Nothing is added to the source models. See the Derived Entities guide.

## Paste into your app's CLAUDE.md

When a component includes `ReactiveComponent`: keep template output to primitives, declare `live_action` params, and load the component class before triggering broadcasts from a console.
```

**Step 2: Verify the claims against the code**

Run:
```bash
grep -n "UnsafeBroadcastValueError\|class CompileError\|def dom_id_for\|permit(\*action_config" lib/reactive_component.rb | head
```
Expected: one hit per pattern. If any is missing, the rule is stale; fix the rule, not the code.

**Step 3: Link it from the README**

Append to the links line at `README.md:12`:

```markdown
 | **[AGENTS.md](AGENTS.md)**
```

**Step 4: Commit**

```bash
git add AGENTS.md README.md
git commit -m "Add AGENTS.md with the rules agents get wrong"
```

---

### Task 5: Changelog and PR

**Files:**
- Modify: `CHANGELOG.md:1-3`

**Step 1: Add an Unreleased section above `## [0.8.0]`**

```markdown
## [Unreleased]

### Added
- The docs site publishes `llms.txt` and `llms-full.txt` for AI agents, the
  Markdown guides ship inside the gem, and `AGENTS.md` lists the rules agents
  get wrong.

```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "Note agent-friendly docs in the changelog"
```

**Step 3: Push and open the PR**

Branch name: `feat/agent-friendly-docs`. Use @draft-pr for the description. Two to four sentences: agents had to scrape the site page by page; now one URL or the installed gem carries the full manual, and `AGENTS.md` fronts the gotchas. No tool attribution in the body.

**Step 4: Confirm the deploy**

After merge, wait for the `Deploy docs` workflow on `main`, then:

```bash
gh run list --workflow docs.yml --branch main --limit 1
```
Expected: `success`. Then open https://lluzak.github.io/reactive_component/llms-full.txt in a browser and confirm it starts with the ReactiveComponent description and ends with the Troubleshooting page. `curl` is blocked in this environment; use the browser.

---

## Out of scope

- An MCP server or a docs chatbot. `llms-full.txt` gives agents nearly all the value.
- Rewriting existing guides. The DSL reference is already exhaustive; new features keep landing there first.
- A tag-triggered GitHub release workflow. Separate PR.
