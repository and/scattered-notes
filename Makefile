.PHONY: project build run test e2e-test clean

project:
	xcodegen generate

build:
	xcodebuild build -project ScatteredNotes.xcodeproj -scheme ScatteredNotes -derivedDataPath ./build/DerivedData

test:
	xcodebuild test -project ScatteredNotes.xcodeproj -scheme ScatteredNotes -destination 'platform=macOS' -derivedDataPath ./build/DerivedData

e2e-test:
	xcodebuild test -project ScatteredNotes.xcodeproj -scheme ScatteredNotes -destination 'platform=macOS' -derivedDataPath ./build/DerivedData -only-testing:ScatteredNotesTests/EndToEndFeatureTests

run: build
	open ./build/DerivedData/Build/Products/Debug/ScatteredNotes.app

clean:
	rm -rf ./build/DerivedData
