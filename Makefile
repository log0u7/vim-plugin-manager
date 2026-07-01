.DEFAULT_GOAL := help

BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
TAG    := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "no-tag")
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

ifeq ($(origin VERSION), undefined)
	ARCHIVE_VERSION := $(TAG)
else
	ARCHIVE_VERSION := $(VERSION)
endif
ARCHIVE_NAME := vim-plugin-manager-$(ARCHIVE_VERSION)

# ---------------------------------------------------------------------------
# Test configuration
# Keep VADER_SHA in sync with .github/workflows/test.yml and .gitlab-ci.yml
# ---------------------------------------------------------------------------
VIM         ?= vim
VADER_DIR   ?= vader.vim
VADER_SHA   := 429b669e6158be3a9fc110799607c232e6ed8e29
VADER_TESTS ?= tests/*.vader
VIMRC_TEST  := .vaderrc.vim

.PHONY: help update-version archive test test-ci clean

help:
	@echo ""
	@echo "Test:"
	@echo "  make test                                    # Run Vader tests (interactive TUI)"
	@echo "  make test-ci                                 # Run Vader tests (headless, same as CI)"
	@echo "  make clean                                   # Remove generated test artifacts"
	@echo ""
	@echo "Release:"
	@echo "  make update-version                          # Update all *.vim, *.txt, README.md with Git version"
	@echo "  make update-version VERSION=1.6              # Update all with custom version"
	@echo "  make update-version FILE=path/to/file        # Update only that file with Git version"
	@echo "  make update-version FILE=path VERSION=1.6    # Update only that file with custom version"
	@echo "  make archive                                 # Create archive from latest tag"
	@echo "  make archive VERSION=1.3.5                   # Create archive from specified version tag"
	@echo ""

# ---------------------------------------------------------------------------
# Test targets
# ---------------------------------------------------------------------------

# Auto-clone vader.vim at the pinned SHA if the directory does not exist yet.
# Make treats the directory name as a file target: once present it is never
# rebuilt, so re-running make test does not trigger a redundant clone.
$(VADER_DIR):
	git clone https://github.com/junegunn/vader.vim.git $(VADER_DIR)
	git -C $(VADER_DIR) checkout $(VADER_SHA)

# Generate the minimal vimrc that points Vim at the plugin and Vader.
$(VIMRC_TEST):
	@echo "set rtp^=$(CURDIR)" > $(VIMRC_TEST)
	@echo "set rtp+=$(CURDIR)/$(VADER_DIR)" >> $(VIMRC_TEST)
	@echo "filetype off" >> $(VIMRC_TEST)
	@echo "syntax off" >> $(VIMRC_TEST)

test: $(VADER_DIR) $(VIMRC_TEST)
	@echo "==> Running Vader tests..."
	$(VIM) -Nu $(VIMRC_TEST) -c 'Vader! $(VADER_TESTS)'

test-ci: $(VADER_DIR) $(VIMRC_TEST)
	@echo "==> Running Vader tests (headless)..."
	$(VIM) -es -Nu $(VIMRC_TEST) -c 'Vader! $(VADER_TESTS)'

clean:
	@rm -f $(VIMRC_TEST)

# ---------------------------------------------------------------------------
# Release targets
# ---------------------------------------------------------------------------

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
