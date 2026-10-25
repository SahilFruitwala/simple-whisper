APP := build/Build/Products/Release/Simple Wisper.app

# Signing identity: the local self-signed cert by default; CI passes SIGN_IDENTITY=- (ad-hoc).
SIGN_IDENTITY ?= Simple Wisper Local
# Release versioning: overrides MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml.
VERSION ?=
BUILD_NUMBER ?=

XCB := xcodebuild -project SimpleWisper.xcodeproj -scheme SimpleWisper -configuration Release \
	-derivedDataPath build -clonedSourcePackagesDirPath build/spm -skipMacroValidation \
	CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
	$(if $(VERSION),MARKETING_VERSION=$(VERSION)) \
	$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))

.PHONY: project icons build install cert dmg clean

icons:
	swift scripts/make-icons.swift .

project:
	xcodegen generate -q

cert:
	./scripts/make-cert.sh

build: project
	$(XCB) build | xcbeautify 2>/dev/null || $(XCB) build -quiet

install: build
	rm -rf "/Applications/Simple Wisper.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Simple Wisper.app"

dmg: build
	rm -rf build/dmg && mkdir -p build/dmg
	cp -R "$(APP)" build/dmg/ && ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Simple Wisper" -srcfolder build/dmg -ov -format UDZO build/SimpleWisper.dmg

clean:
	rm -rf build SimpleWisper.xcodeproj
