## NotificationNanny convenience targets
##
## Running tests without Xcode (Command Line Tools only)
## requires symlinking the Testing framework into the build
## directory — handled automatically by `make test` below.
##
## With Xcode installed, plain `swift test` works directly.

.PHONY: build test clean

CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_DEV_LIB   := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
BUILD_DEBUG    := .build/arm64-apple-macosx/debug

build:
	swift build

test:
	swift build --build-tests
	@# Symlink CLT's Testing.framework into the build dir so the test
	@# binary can find it at runtime via @loader_path/../../../.
	@# Skipped silently when using full Xcode (framework not at CLT path).
	@if [ -d "$(CLT_FRAMEWORKS)/Testing.framework" ] && \
	    [ ! -e "$(BUILD_DEBUG)/Testing.framework" ]; then \
		echo "Symlinking Testing.framework for CLT…"; \
		ln -sf "$(CLT_FRAMEWORKS)/Testing.framework" "$(BUILD_DEBUG)/Testing.framework"; \
	fi
	@if [ -f "$(CLT_DEV_LIB)/lib_TestingInterop.dylib" ] && \
	    [ ! -e "$(BUILD_DEBUG)/lib_TestingInterop.dylib" ]; then \
		echo "Symlinking lib_TestingInterop.dylib for CLT…"; \
		ln -sf "$(CLT_DEV_LIB)/lib_TestingInterop.dylib" "$(BUILD_DEBUG)/lib_TestingInterop.dylib"; \
	fi
	swift test --skip-build

clean:
	swift package clean
