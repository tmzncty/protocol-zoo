.PHONY: validate fixtures capture real-app sctp remaining era2-fixtures era2-capture era2-network era2-ipv6 era2-rip era2-ppp era2-validate era2-static era3-validate test-capture-paths test-kali-capture-wrappers test-era3-validator test-check-order capabilities experiment clean check
validate:
	./scripts/experiment.sh validate
fixtures:
	./scripts/experiment.sh fixtures
capture:
	./scripts/experiment.sh capture
real-app:
	./scripts/experiment.sh real-app
sctp:
	./scripts/experiment.sh sctp
remaining:
	./scripts/experiment.sh remaining
capabilities:
	./scripts/experiment.sh capabilities
experiment:
	@./scripts/experiment.sh
clean:
	./scripts/experiment.sh clean
era2-fixtures:
	./scripts/era2-fixtures.sh
era2-capture:
	./scripts/era2-capture.sh
era2-network:
	./scripts/era2-network-capture.sh
era2-ipv6:
	./scripts/era2-ipv6-capture.sh
era2-rip:
	./scripts/era2-rip-capture.sh
era2-ppp:
	./scripts/era2-ppp-capture.sh
era2-validate:
	./scripts/era2-validate.sh
era2-static:
	./scripts/era2-static-results.sh
era3-validate:
	./scripts/era3-validate.sh
test-capture-paths:
	sh ./tests/capture-path-regression.sh
test-kali-capture-wrappers:
	sh ./tests/kali-capture-wrapper-regression.sh
test-era3-validator:
	sh ./tests/era3-validator-regression.sh
test-check-order:
	+sh ./tests/check-order-regression.sh "$(MAKE)"
# Generators rewrite evidence consumed by validation. Keep each phase parallel,
# but finish every generator before starting any reader. Standalone validation
# targets deliberately retain their existing no-generation behavior.
check:
	$(MAKE) fixtures capabilities era2-fixtures era2-static
	$(MAKE) validate era2-validate test-capture-paths test-kali-capture-wrappers test-era3-validator era3-validate test-check-order
