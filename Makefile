SHELL := /bin/bash
REPO := $(shell pwd)

BATS_IMAGE       := bats/bats:1.10.0
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.9.0
HARNESS_IMAGE    := vivado-test-harness:local
TEST_SCRATCH     := /tmp/vivado-it

BASE_IMAGE      := vivado-base:22.04
RAW_IMAGE       := vivado-tools:2024.1.2-raw
FINAL_IMAGE     := vivado:2024.1.2
VITIS_RAW_IMAGE := vivado-vitis:2024.1.2-raw
VITIS_IMAGE     := vivado-vitis:2024.1.2

# MEDIA_DIR has no default: any default is one machine's path and silently
# wrong everywhere else. Pass it per invocation, or export it.
DEST      := /tools/Xilinx

.PHONY: lint test-unit harness test-integration base install verify-media \
        final build test test-smoke add-vitis test-vitis test-all acceptance \
        require-media

# Fails before anything mounts, hashes or installs. The scripts guard too, for
# direct invocation; only here can the message name the target that was typed.
require-media:
	@test -n "$(MEDIA_DIR)" || { \
	  echo "ERROR: MEDIA_DIR is not set." >&2; \
	  echo "       It must name the directory holding the two AMD ISOs:" >&2; \
	  echo "         Xilinx_Unified_2024_1_0522_2023.iso" >&2; \
	  echo "         Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso" >&2; \
	  echo "       e.g. make MEDIA_DIR=/path/to/Xilinx_2024.1 $(or $(MAKECMDGOALS),build)" >&2; \
	  exit 1; }

lint:
	docker run --rm -v "$(REPO):/mnt" -w /mnt $(SHELLCHECK_IMAGE) \
		-x $$(find lib scripts -name '*.sh' | sort)

test-unit:
	docker run --rm -v "$(REPO):/code" -w /code $(BATS_IMAGE) test/unit

harness:
	docker build -f docker/Dockerfile.testharness -t $(HARNESS_IMAGE) .

base:
	docker build -f docker/Dockerfile.base -t $(BASE_IMAGE) .

install: require-media base
	MEDIA_DIR=$(MEDIA_DIR) DEST=$(DEST) bash scripts/install.sh

verify-media: require-media
	@cd $(MEDIA_DIR) && sha256sum \
		Xilinx_Unified_2024_1_0522_2023.iso \
		Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso \
		> $(REPO)/config/media.sha256
	@echo "verify-media: recorded hashes; stage 2 will now use verified mode"

# Ordering is encoded as real prerequisites, not as a hopeful listing.
# `make -j build` with independent targets can build the final image before
# stage 2 has produced the raw image it is FROM.
final: install
	docker build --network=none -f docker/Dockerfile.final \
		--build-arg BASE_IMAGE=$(RAW_IMAGE) -t $(FINAL_IMAGE) .

build: final

test-integration: harness final
	@mkdir -p $(TEST_SCRATCH)
	docker run --rm -v "$(REPO):/code" -w /code \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v "$(TEST_SCRATCH):$(TEST_SCRATCH)" \
		-e "TEST_SCRATCH=$(TEST_SCRATCH)" \
		$(HARNESS_IMAGE) test/integration

# The spec names `make test` as criterion 3's entry point; keep both.
test: test-smoke

test-smoke: final
	bash test/run-smoke.sh

# Phony and unkeyed: it reruns in full on every separate `make` invocation.
# Depend on it (as test-vitis does) rather than invoking it beforehand.
add-vitis: require-media install
	MEDIA_DIR=$(MEDIA_DIR) bash scripts/add-vitis.sh
	docker build --network=none -f docker/Dockerfile.final \
		--build-arg BASE_IMAGE=$(VITIS_RAW_IMAGE) -t $(VITIS_IMAGE) .

# The variant reuses Dockerfile.final, so entrypoint, HOME handling, workdir
# and environment are identical to the default image by construction rather
# than by duplication.
test-vitis: harness add-vitis
	@mkdir -p $(TEST_SCRATCH)
	docker run --rm -v "$(REPO):/code" -w /code \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v "$(TEST_SCRATCH):$(TEST_SCRATCH)" \
		-e "TEST_SCRATCH=$(TEST_SCRATCH)" \
		$(HARNESS_IMAGE) test/vitis

test-all: lint test-unit test-integration test-smoke
	@echo "test-all: default-image checks passed"

# Full sweep from a clean state. test-all alone is NOT an acceptance run:
# it builds nothing and vitis.bats needs an image that only add-vitis
# produces, so on a fresh machine it would fail -- or, worse, pass only
# because an earlier manual task happened to leave images behind.
acceptance: lint test-unit test-integration test-smoke test-vitis
	@echo "acceptance: all nine criteria exercised from freshly built images"
