.PHONY: build app run ci release clean

APP_NAME := BlackBar

build:
	swift build -c release

app: build
	./Scripts/package_app.sh release
	rm -rf "build/$(APP_NAME).app"
	mkdir -p build
	APP_DIR=".build/apple/Products/Release/$(APP_NAME).app"; \
	if [ ! -d "$$APP_DIR" ]; then APP_DIR="$$(find .build -path "*/release/$(APP_NAME).app" -type d | head -n 1)"; fi; \
	test -n "$$APP_DIR"; \
	ditto "$$APP_DIR" "build/$(APP_NAME).app"

run: app
	open "build/$(APP_NAME).app"

ci:
	swift package resolve
	swift build -c release
	$(MAKE) app

release:
	./Scripts/release.sh

clean:
	rm -rf .build build *.zip *.dSYM
