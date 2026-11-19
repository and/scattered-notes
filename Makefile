.PHONY: project build run test e2e-test ui-test clean linux-run linux-test linux-install

project:
	xcodegen generate

build:
	xcodebuild build -project ScatteredNotes.xcodeproj -scheme ScatteredNotes -derivedDataPath ./build/DerivedData

test:
	xcodebuild test -project ScatteredNotes.xcodeproj -scheme ScatteredNotes -destination 'platform=macOS' -derivedDataPath ./build/DerivedData

e2e-test:
	xcodebuild test -project ScatteredNotes.xcodeproj -scheme ScatteredNotes -destination 'platform=macOS' -derivedDataPath ./build/DerivedData -only-testing:ScatteredNotesTests/EndToEndFeatureTests

ui-test:
	xcodebuild test -project ScatteredNotes.xcodeproj -scheme ScatteredNotesUITests -destination 'platform=macOS' -derivedDataPath ./build/DerivedData

run: build
	open ./build/DerivedData/Build/Products/Debug/ScatteredNotes.app

clean:
	rm -rf ./build/DerivedData

# Linux: the Avalonia app in windows/ runs on Ubuntu too. Needs the .NET 10 SDK.
DOTNET ?= $(shell command -v dotnet || echo $(HOME)/.dotnet/dotnet)

linux-run:
	DOTNET_ROOT=$(dir $(DOTNET)) $(DOTNET) run --project windows/src/ScatteredNotes.App

linux-test:
	$(DOTNET) test windows

linux-install:
	scripts/install-linux.sh
