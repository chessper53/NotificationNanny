## NotificationNanny convenience targets
##
## With Xcode installed:   swift test  (or just open in Xcode)
## With CLT only:          make test   (handles framework search path + symlinks)

.PHONY: build test clean

CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_DEV_LIB   := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
BUILD_DEBUG    := .build/arm64-apple-macosx/debug

# Detect whether we have full Xcode or only CLT.
# xcode-select -p returns /Library/Developer/CommandLineTools when CLT-only.
DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)
IS_CLT        := $(filter /Library/Developer/CommandLineTools,$(DEVELOPER_DIR))

build:
	swift build

test:
ifdef IS_CLT
	# CLT-only: point the Swift compiler at the CLT Testing framework.
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
	# Full Xcode: Testing is in the SDK, nothing special needed.
	swift test
endif

clean:
	swift package clean
