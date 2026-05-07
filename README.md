# Sonda Red Web Presence

This repository builds both `sonda.red` and `blog.sonda.red` from the same branch.

The shared Hugo and Hextra configuration lives in `hugo.yaml`. Domain-specific overlays select different content mounts and output directories:

- `hugo.root.yaml` builds the landing site from `content/root` into `public-root`
- `hugo.blog.yaml` builds the blog from `content/blog` into `public-blog`

## Local Builds

```bash
make root-build
make blog-build
```

For local preview:

```bash
make root-serve
make blog-serve
```

## Cloudflare Pages

Use two Cloudflare Pages projects pointing at the same GitHub repo and branch.

| Project | Domain | Build command | Output directory |
| --- | --- | --- | --- |
| `sonda-web` | `sonda.red` | `make root-build` | `public-root` |
| `sonda-blog` | `blog.sonda.red` | `make blog-build` | `public-blog` |

Both builds reuse the same Hextra theme module, shared navigation, shared layouts, and shared assets.
