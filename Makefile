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

# Define archive name using VERSION or TAG
ifeq ($(origin VERSION), undefined)
	ARCHIVE_VERSION := $(TAG)
else
	ARCHIVE_VERSION := $(VERSION)
endif
ARCHIVE_NAME := vim-plugin-manager-$(ARCHIVE_VERSION)

.PHONY: help update-version archive

help:
	@echo ""
	@echo "Usage:"
	@echo "  make update-version                          # Update all *.vim and *.txt recursively with Git version"
	@echo "  make update-version VERSION=1.6              # Update all with custom version"
	@echo "  make update-version FILE=chemin/fichier      # Update only that file with Git version"
	@echo "  make update-version FILE=chemin VERSION=1.6  # Update only that file with custom version"
	@echo "  make archive                                 # Create archive from latest tag"
	@echo "  make archive VERSION=1.3.5                   # Create archive from specified version tag"
	@echo ""

update-version:
	@echo "Updating version to: $(VERSION_STRING)"
	@if [ -n "$(FILE)" ]; then \
		echo "Processing $(FILE)..."; \
		sed -i -E 's/(^.*Version[ ]*:).*/\1 $(VERSION_STRING)/' "$(FILE)"; \
	else \
		find . -type f \( -name "*.vim" -o -name "*.txt" -o -name "README.md" \) | while read file; do \
			echo "Processing $$file..."; \
			sed -i -E 's/(^.*Version[ ]*:).*/\1 $(VERSION_STRING)/' "$$file"; \
		done; \
	fi

archive:
	@echo "Creating archive $(ARCHIVE_NAME).tar.gz from tag $(ARCHIVE_VERSION)"
	@if [ "$(ARCHIVE_VERSION)" = "no-tag" ]; then \
		echo "Error: No tag found. Please specify VERSION or create a tag first."; \
		exit 1; \
	fi
	@git archive --format=tar.gz --prefix=$(ARCHIVE_NAME)/ -o $(ARCHIVE_NAME).tar.gz $(ARCHIVE_VERSION)
	@echo "Archive created successfully: $(ARCHIVE_NAME).tar.gz"