.DEFAULT_GOAL := help

BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
TAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "no-tag")
COMMIT := $(shell git rev-parse --short HEAD)

ifeq ($(origin VERSION), undefined)
	ifeq ($(filter $(BRANCH),main master),)
		VERSION_STRING := $(BRANCH) $(TAG) $(COMMIT)
	else
		VERSION_STRING := $(TAG) $(COMMIT)
	endif
else
	VERSION_STRING := $(VERSION)
endif

.PHONY: help update-version

help:
	@echo ""
	@echo "Usage:"
	@echo "  make update-version                          # Update all *.vim and *.txt recursively with Git version"
	@echo "  make update-version VERSION=1.6              # Update all with custom version"
	@echo "  make update-version FILE=chemin/fichier      # Update only that file with Git version"
	@echo "  make update-version FILE=chemin VERSION=1.6  # Update only that file with custom version"
	@echo ""

update-version:
	@echo "Updating version to: $(VERSION_STRING)"
	@if [ -n "$(FILE)" ]; then \
		echo "Processing $(FILE)..."; \
		sed -i -E 's/(^.*Version[ ]*:).*/\1 $(VERSION_STRING)/' "$(FILE)"; \
	else \
		find . -type f \( -name "*.vim" -o -name "*.txt" \) | while read file; do \
			echo "Processing $$file..."; \
			sed -i -E 's/(^.*Version[ ]*:).*/\1 $(VERSION_STRING)/' "$$file"; \
		done; \
	fi
