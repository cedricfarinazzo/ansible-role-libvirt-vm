# Define supported distributions
SUPPORTED_DISTROS := debian13 ubuntu2404 ubuntu2604
DEFAULT_DISTRO := debian13
SCENARIOS := uefi options absent check failure virtualdomain

.PHONY: molecule-test molecule-test-all lint help check-prereqs test $(addprefix molecule-test-,$(SCENARIOS))

help:
	@echo "Available targets:"
	@echo "  molecule-test              - Run the default scenario on $(DEFAULT_DISTRO)"
	@echo "  test                       - Alias for molecule-test"
	@echo "  molecule-test-all          - Run the default scenario on every supported distribution, in parallel"
	@echo "  molecule-test-<distro>     - Run the default scenario on one distribution"
	@echo "  molecule-test-uefi         - An EFI VM: OVMF loader and NVRAM template"
	@echo "  molecule-test-options      - No validation or package, other directories, shared VM defaults"
	@echo "  molecule-test-absent       - VMs removed one by one, then all"
	@echo "  molecule-test-check        - Check mode on a fresh host: nothing written"
	@echo "  molecule-test-failure      - The failure paths"
	@echo "  molecule-test-virtualdomain - Pacemaker's VirtualDomain starts a rendered file"
	@echo "  lint                       - Run ansible-lint"
	@echo ""
	@echo "Supported distributions:"
	@for distro in $(SUPPORTED_DISTROS); do \
		echo "  - $$distro"; \
	done

molecule-test: check-prereqs
	./run-tests.sh $(DEFAULT_DISTRO)

test: molecule-test

molecule-test-all: check-prereqs
	./run-tests.sh $(SUPPORTED_DISTROS)

$(addprefix molecule-test-,$(SCENARIOS)): molecule-test-%: check-prereqs
	./run-tests.sh -s $* $(DEFAULT_DISTRO)

molecule-test-%: check-prereqs
	./run-tests.sh $*

lint:
	ansible-lint

check-prereqs:
	@command -v ansible >/dev/null 2>&1 || { echo "Ansible is not installed"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "Docker is not installed"; exit 1; }
