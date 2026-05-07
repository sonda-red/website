DOCS_PORT ?= 1313
ROOT_PORT ?= 1314
HUGO ?= hugo
HUGO_CACHE_DIR ?= /tmp/sonda-red-hugo-cache

.PHONY: root-build
root-build: ## Build the landing site for sonda.red into public-root.
	"$(HUGO)" --config hugo.yaml,hugo.root.yaml --cacheDir "$(HUGO_CACHE_DIR)" --destination public-root --gc --minify

.PHONY: blog-build
blog-build: ## Build the blog site for blog.sonda.red into public-blog.
	"$(HUGO)" --config hugo.yaml,hugo.blog.yaml --cacheDir "$(HUGO_CACHE_DIR)" --destination public-blog --gc --minify

.PHONY: docs-build
docs-build: ## Build the Hugo + Hextra blog site.
	"$(MAKE)" blog-build

.PHONY: docs-serve
docs-serve: ## Serve the blog locally with Hugo; set DOCS_PORT to override 1313.
	"$(MAKE)" blog-serve

.PHONY: blog-serve
blog-serve: ## Serve the blog locally with Hugo; set DOCS_PORT to override 1313.
	"$(HUGO)" server --config hugo.yaml,hugo.blog.yaml --cacheDir "$(HUGO_CACHE_DIR)" --buildDrafts --disableFastRender --bind 0.0.0.0 --port "$(DOCS_PORT)"

.PHONY: root-serve
root-serve: ## Serve the landing site locally with Hugo; set ROOT_PORT to override 1314.
	"$(HUGO)" server --config hugo.yaml,hugo.root.yaml --cacheDir "$(HUGO_CACHE_DIR)" --buildDrafts --disableFastRender --bind 0.0.0.0 --port "$(ROOT_PORT)"
