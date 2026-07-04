.PHONY: build test bundle run clean release help

help: ## 타깃 목록 표시
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-18s %s\n", $$1, $$2}'

build: ## 디버그 빌드
	swift build

test: ## 전체 테스트 실행
	swift test

bundle: ## release 빌드 + .app 번들 조립 (build/SnapScreen.app)
	Scripts/bundle.sh release

run: ## 디버그 번들 빌드 후 앱 실행 (기존 인스턴스 종료)
	Scripts/run.sh

clean: ## 빌드 산출물 삭제
	rm -rf .build build

release: ## 릴리스 태그 생성+푸시 → GitHub Release 자동 생성. 사용법: make release VERSION=v0.1.0
	Scripts/release.sh $(VERSION)
