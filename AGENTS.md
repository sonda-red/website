## Purpose of this repo

This repo powers the sonda.red personal web presence.

Sonda Red is not a company, startup, vendor, or product platform. It is my personal engineering lab for Kubernetes-native AI infrastructure, workload identity, inference systems, operators, and platform engineering.

The site should make the relationship clear:

- `sonda.red` is the personal lab wrapper.
- `blog.sonda.red` is the notebook and article archive.
- `kleym.sonda.red` is dedicated project documentation for Kleym.
- `github.com/sonda-red` is the source namespace.

## Tone

Write in a direct, technical, personal voice.

Use first person when appropriate.

Good examples:

- “Sonda Red is my personal engineering lab for Kubernetes-native AI infrastructure.”
- “I use this site to publish experiments, notes, and small open-source projects.”
- “Kleym is an experimental identity compiler for Kubernetes-native inference workloads.”
- “These are lab notes from things I tested, broke, or changed my mind about.”

Avoid fake-company language.

Do not use:

- “we”
- “our customers”
- “mission”
- “enterprise-grade”
- “AI governance platform”
- “secure inference platform for modern teams”
- “products”
- “solutions”
- “redefining”
- “for the AI era”

The site should feel like a serious engineer’s lab, not a vendor homepage.

## Branding rules

Sonda Red may have a visual identity, logo, theme, and project names. That is fine.

Do not hide the personal authorship behind the brand.

Prefer:

> sonda.red is a personal engineering lab by Kalin Daskalov.

Avoid:

> sonda.red builds secure AI infrastructure products.

The brand should act as a namespace for work, not as a pretend company.

## Diagram handling

Prefer the simplest diagram representation that works in a Markdown blog post.

For small or medium article diagrams, use inline fenced `text` code blocks with ASCII/Unicode box drawing. Do not default to Mermaid, browser-rendered diagrams, shortcodes, generated assets, or custom CSS for diagrams.

If a diagram is authored in D2, Graphviz, or another text diagram tool, it is fine to use the tool to draft the diagram, but paste the final readable text output directly into the post unless I explicitly ask to keep a generated-asset pipeline.

Avoid adding new diagram build targets, shortcode wrappers, CSS centering rules, or Hugo asset loading just to render diagrams in a blog article. Add that machinery only when explicitly requested or when a diagram is too large to maintain inline.

Use fenced `text`, not `bash`, for rendered ASCII/Unicode diagrams. Use `bash` only for real shell snippets.
