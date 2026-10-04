# SwiftPM за замовчуванням вмикає XCBuild, який без повного Xcode не стартує,
# тому скрізь тримаємось native-збірки.
SWIFT_FLAGS = --build-system native
APP = /Applications/NotchMeter.app

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

# Збірка й так кладе застосунок у /Applications; ціль лишилась для звички.
install: app

stop:
	-@pkill -x NotchMeter 2>/dev/null || true

clean:
	rm -rf .build build
