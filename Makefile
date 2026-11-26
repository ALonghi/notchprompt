# Local, sandboxed build. See scripts/sandboxed.sh.
.PHONY: build run install verify clean

build run install verify:
	@./scripts/sandboxed.sh $@

clean:
	rm -rf build/local
