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

.PHONY: help archive tag test test-ci test-async clean

help:
	@echo ""
	@echo "Test:"
	@echo "  make test                                    # Run Vader tests (interactive TUI)"
	@echo "  make test-ci                                 # Run Vader tests (headless, same as CI)"
	@echo "  make test-async                              # Run async smoke test under a pty (requires util-linux script)"
	@echo "  make clean                                   # Remove generated test artifacts"
	@echo ""
	@echo "Release:"
	@echo "  make tag VERSION=vX.Y.Z                      # Create annotated tag and push (--follow-tags)"
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
	@echo "let g:plugin_manager_test_force_sync = 1" >> $(VIMRC_TEST)

test: $(VADER_DIR) $(VIMRC_TEST)
	@echo "==> Running Vader tests..."
	$(VIM) -Nu $(VIMRC_TEST) -c 'Vader! $(VADER_TESTS)'

test-ci: $(VADER_DIR) $(VIMRC_TEST)
	@echo "==> Running Vader tests (headless)..."
	$(VIM) -es -Nu $(VIMRC_TEST) -c 'Vader! $(VADER_TESTS)'

# Run the real async smoke test under a pty so Vim's event loop is active.
# Requires util-linux 'script' (available on all targeted Linux distributions).
# Exit code: 0 = all assertions passed, 1 = one or more failures.
test-async:
	@echo "==> Running async smoke test (pty mode)..."
	@rm -f /tmp/pm_async_smoke.log
	@script -qec "$(VIM) -N -u tests/async_smoke.vim" /dev/null ; \
	  EXIT=$$? ; \
	  cat /tmp/pm_async_smoke.log 2>/dev/null || true ; \
	  exit $$EXIT

clean:
	@rm -f $(VIMRC_TEST)

# ---------------------------------------------------------------------------
# Release targets
# ---------------------------------------------------------------------------

tag:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required (e.g. make tag VERSION=v2.1.3)"; \
		exit 1; \
	fi
	@echo "$(VERSION)" | grep -q '^v' || { \
		echo "Error: VERSION must start with v (e.g. v2.1.3)"; \
		exit 1; \
	}
	@VERSION_NO_V=$$(echo "$(VERSION)" | sed 's/^v//'); \
	if ! grep -q "^## \[$$VERSION_NO_V\]" CHANGELOG.md; then \
		echo "Error: No CHANGELOG entry found for $(VERSION)"; \
		exit 1; \
	fi
	git tag -a $(VERSION) -m "$(VERSION)"
	git push origin main --follow-tags

archive:
	@echo "Creating archive $(ARCHIVE_NAME).tar.gz from tag $(ARCHIVE_VERSION)"
	@if [ "$(ARCHIVE_VERSION)" = "no-tag" ]; then \
		echo "Error: No tag found. Please specify VERSION or create a tag first."; \
		exit 1; \
	fi
	@git archive --format=tar.gz --prefix=$(ARCHIVE_NAME)/ -o $(ARCHIVE_NAME).tar.gz $(ARCHIVE_VERSION)
	@echo "Archive created successfully: $(ARCHIVE_NAME).tar.gz"
