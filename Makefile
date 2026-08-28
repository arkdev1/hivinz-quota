SCHEME  := Quota
PROJECT := Quota.xcodeproj
CONFIG  ?= Debug
BUILD   := build
APP     := $(BUILD)/Build/Products/$(CONFIG)/$(SCHEME).app

.PHONY: generate build run release clean

## Regenerate the Xcode project from project.yml
generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	           -derivedDataPath $(BUILD) build

run: build
	@pkill -x $(SCHEME) || true
	open $(APP)

release:
	$(MAKE) build CONFIG=Release

clean:
	rm -rf $(BUILD) $(PROJECT) Support/Info.plist
