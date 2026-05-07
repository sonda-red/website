PORT ?= 1313
HUGO ?= hugo
HUGO_CACHE_DIR ?= /tmp/sonda-red-hugo-cache

.PHONY: build
build: ## Build the site into public.
	"$(HUGO)" --config hugo.yaml --cacheDir "$(HUGO_CACHE_DIR)" --destination public --cleanDestinationDir --gc --minify

.PHONY: serve
serve: ## Serve the site locally with Hugo; set PORT to override 1313.
	"$(HUGO)" server --config hugo.yaml --cacheDir "$(HUGO_CACHE_DIR)" --buildDrafts --disableFastRender --bind 0.0.0.0 --port "$(PORT)"
