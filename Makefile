APP_NAME = FallbackWiFi
BUNDLE_NAME = FallbackWiFi.app
EXECUTABLE = FallbackWiFi
BUILD_DIR = .build/release
BUNDLE_DIR = .build/app/$(BUNDLE_NAME)
IDENTITY ?= -

.PHONY: all build bundle sign run test clean

all: bundle sign

build:
	swift build -c release

bundle: build
	@if [ -d "$(BUNDLE_DIR)" ]; then trash "$(BUNDLE_DIR)"; fi
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(EXECUTABLE) $(BUNDLE_DIR)/Contents/MacOS/
	@cp Info.plist $(BUNDLE_DIR)/Contents/
	@cp assets/project-icon.icns $(BUNDLE_DIR)/Contents/Resources/
	@echo "Bundle created at $(BUNDLE_DIR)"

sign: bundle
	codesign --deep --force --sign "$(IDENTITY)" --options=runtime $(BUNDLE_DIR)
	@echo "Signed with identity: $(IDENTITY)"

run: all
	@open $(BUNDLE_DIR)

test:
	swift test

clean:
	@if [ -d ".build/app" ]; then trash ".build/app"; fi
	@if [ -d "dist" ]; then trash "dist"; fi
	swift package clean
	@echo "Cleaned"
