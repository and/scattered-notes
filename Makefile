.PHONY: project build run test e2e-test ui-test clean

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
