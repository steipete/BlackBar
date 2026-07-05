.PHONY: build app run test ci release clean

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

test:
	swift test
	./Tests/Scripts/codesign-app-test.sh
	./Tests/Scripts/sign-and-notarize-test.sh

ci: test
	swift package resolve
	swift build -c release
	$(MAKE) app

release:
	./Scripts/release.sh

clean:
	rm -rf .build build *.zip *.dSYM
