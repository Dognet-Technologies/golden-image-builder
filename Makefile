# Golden image Debian 13: comandi principali. Le chiavi stanno fuori dal repository:
#   make keys KEYS=~/golden-keys          (una volta)
#   make image PROFILE=web VARIANT=immutable KEYS=~/golden-keys
#   make test-all KEYS=~/golden-keys
PROFILE ?= web
VARIANT ?= mutable
KEYS    ?=

.PHONY: tools keys test-creds rootfs image check sbom vulns release test test-all clean

tools:
	./tools.sh

keys:
	@test -n "$(KEYS)" || { echo "serve KEYS=<directory fuori dal repository>"; exit 1; }
	tools/sb-keys.sh $(KEYS)
	tools/update-key.sh $(KEYS)

test-creds:
	tools/test-creds.sh

rootfs:
	VARIANT=$(VARIANT) GOLDEN_KEYS=$(KEYS) ./build.sh $(PROFILE)

image: rootfs
	VARIANT=$(VARIANT) GOLDEN_KEYS=$(KEYS) ./image.sh $(PROFILE)

check:
	VARIANT=$(VARIANT) tests/check-rootfs.sh $(PROFILE)
	VARIANT=$(VARIANT) tests/check-packages.sh $(PROFILE)

sbom:
	VARIANT=$(VARIANT) tools/sbom.sh $(PROFILE)

vulns: sbom
	VARIANT=$(VARIANT) tools/vulnscan.sh $(PROFILE)

release:
	VARIANT=$(VARIANT) GOLDEN_KEYS=$(KEYS) tools/release.sh $(PROFILE)

test: test-creds
	GOLDEN_KEYS=$(KEYS) tests/run-all.sh $(PROFILE):$(VARIANT)

test-all: test-creds
	GOLDEN_KEYS=$(KEYS) tests/run-all.sh

clean:
	tests/vm.sh stop
	rm -rf out/vm out/reports out/release out/update out/*.raw out/*.sha256 out/logs
