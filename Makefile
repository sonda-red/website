DOCS_PORT ?= 1313
HUGO ?= hugo

.PHONY: docs-build
docs-build: ## Build the Hugo + Hextra blog site.
	"$(HUGO)" --gc --minify

.PHONY: docs-serve
docs-serve: ## Serve the blog locally with Hugo; set DOCS_PORT to override 1313.
	"$(HUGO)" server --buildDrafts --disableFastRender --bind 0.0.0.0 --port "$(DOCS_PORT)"
