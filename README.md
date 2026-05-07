# Sonda Red Web Presence

This repository builds the `sonda.red` site.

Sonda.red is Kalin Daskalov's personal engineering lab for Kubernetes-native AI infrastructure. It is a namespace for notes, experiments, and small open-source projects, not a company, vendor, or product platform.

The Hugo and Hextra configuration lives in `hugo.yaml`. The site uses the standard Hugo content tree:

- `content/_index.md` builds `/`
- `content/about/` builds `/about/`
- `content/notes/` builds `/notes/`

`blog.sonda.red` is now a legacy redirect host only. Its Cloudflare Pages project should deploy `redirects/blog._redirects` as `public/_redirects`; it should not build the Hugo site.

## Local Builds

```bash
make build
```

For local preview:

```bash
make serve
```

The preview port defaults to `1313`; override it with `PORT=...`.

## Cloudflare Pages

Use two Cloudflare Pages projects pointing at the same GitHub repo and branch.

| Project | Domain | Build command | Publish directory |
| --- | --- | --- | --- |
| `sonda-web` | `sonda.red` | `make build` | `public` |
| `sonda-blog` | `blog.sonda.red` | `mkdir -p public && cp redirects/blog._redirects public/_redirects && printf "Redirecting to https://sonda.red/notes/\n" > public/index.html` | `public` |

`make build` runs:

```bash
hugo --config hugo.yaml --cacheDir /tmp/sonda-red-hugo-cache --destination public --cleanDestinationDir --gc --minify
```

The legacy redirects should remain `302` until production paths are verified. After verification, change them to `301`.

## Ownership and Licensing

Content and projects are by Kalin Daskalov unless otherwise noted.

There is no repository-wide `LICENSE` file, so licensing is undecided. Do not add an open license without an explicit decision.

Third-party themes, fonts, icons, and generated theme assets keep their upstream notices. Hextra is used as a Hugo module.
