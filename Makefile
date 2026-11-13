# Convenience targets; make test also supplies Command Line Tools framework paths.

.PHONY: build test clean

CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_DEV_LIB   := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
BUILD_DEBUG    := .build/arm64-apple-macosx/debug

# Detect Command Line Tools installations, which need explicit Testing framework paths.
DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)
IS_CLT        := $(filter /Library/Developer/CommandLineTools,$(DEVELOPER_DIR))

build:
	swift build

test:
ifdef IS_CLT
	# Supply the Testing framework for Command Line Tools.
	swift build --build-tests \
		-Xswiftc -F -Xswiftc "$(CLT_FRAMEWORKS)"
	@if [ ! -e "$(BUILD_DEBUG)/Testing.framework" ]; then \
		echo "Symlinking Testing.framework for CLT…"; \
		ln -sf "$(CLT_FRAMEWORKS)/Testing.framework" "$(BUILD_DEBUG)/Testing.framework"; \
	fi
	@if [ ! -e "$(BUILD_DEBUG)/lib_TestingInterop.dylib" ]; then \
		echo "Symlinking lib_TestingInterop.dylib for CLT…"; \
		ln -sf "$(CLT_DEV_LIB)/lib_TestingInterop.dylib" "$(BUILD_DEBUG)/lib_TestingInterop.dylib"; \
	fi
	swift test --skip-build
else
	swift test
endif

clean:
	swift package clean
