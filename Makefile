DOCS_PORT ?= 1313
ROOT_PORT ?= 1314
HUGO ?= hugo
HUGO_CACHE_DIR ?= /tmp/sonda-red-hugo-cache

.PHONY: root-build
root-build: ## Build the canonical sonda.red site into public.
	"$(HUGO)" --config hugo.yaml --cacheDir "$(HUGO_CACHE_DIR)" --destination public --cleanDestinationDir --gc --minify

.PHONY: blog-build
blog-build: ## Build the legacy blog redirect artifact into public.
	mkdir -p public
	cp redirects/blog._redirects public/_redirects
	printf "Redirecting to https://sonda.red/notes/\n" > public/index.html

.PHONY: docs-build
docs-build: ## Build the canonical sonda.red Hugo site.
	"$(MAKE)" root-build

.PHONY: docs-serve
docs-serve: ## Serve the canonical site locally; set DOCS_PORT to override 1313.
	"$(MAKE)" root-serve ROOT_PORT="$(DOCS_PORT)"

.PHONY: blog-serve
blog-serve: ## Serve the canonical site; the legacy blog host deploys redirects only.
	"$(MAKE)" root-serve ROOT_PORT="$(DOCS_PORT)"

.PHONY: root-serve
root-serve: ## Serve the canonical site locally with Hugo; set ROOT_PORT to override 1314.
	"$(HUGO)" server --config hugo.yaml --cacheDir "$(HUGO_CACHE_DIR)" --buildDrafts --disableFastRender --bind 0.0.0.0 --port "$(ROOT_PORT)"
