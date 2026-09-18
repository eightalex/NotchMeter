# SwiftPM за замовчуванням вмикає XCBuild, який без повного Xcode не стартує,
# тому скрізь тримаємось native-збірки.
SWIFT_FLAGS = --build-system native
APP = build/NotchMeter.app

.PHONY: build app run dump install clean stop icon

build:
	swift build $(SWIFT_FLAGS)

app:
	./Scripts/bundle.sh

# Іконка лежить у репозиторії готовою; ціль потрібна лише після правок у
# Scripts/make-icon.swift.
icon:
	./Scripts/make-icon.swift .

run: app stop
	open $(APP)

dump: build
	./.build/debug/NotchMeter --dump

install: app
	rm -rf /Applications/NotchMeter.app
	cp -R $(APP) /Applications/NotchMeter.app
	@echo "встановлено: /Applications/NotchMeter.app"

stop:
	-@pkill -x NotchMeter 2>/dev/null || true

clean:
	rm -rf .build build
