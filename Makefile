PROJECT_LCNAME=pallet
include el.mk/el.mk

servant-start:
	@cask exec servant start --path "test" &

test: servant-start
	@cask exec ert-runner && cask exec servant stop --path "test"
