commodore_args += -a maxscale-$(instance)

.PHONY: test-uuid
test-uuid: instance = uuid
test-uuid: test

.PHONY: test-default
test-default: instance = defaults
test-default: test
