<p align="center">
  <img src="../../AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  오리지널 Launchpad를 macOS 26+로 다시 가져왔습니다(macOS 15도 지원). 클립보드, 워크플로, 앱 단축키, 윈도우 제어까지.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">웹사이트</a><br>
  <a href="#wechat-donate">☕ WeChat으로 후원</a>
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  한국어 ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a>
</p>

---

## 설치

### 방법 1: DMG 다운로드

[최신 버전 다운로드](https://github.com/umindhub/AppPad/releases/latest) 후 DMG를 열고 AppPad를 '응용 프로그램' 폴더로 드래그하세요.

### 방법 2: Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## 기능

### Launchpad
- 클래식 macOS Launchpad를 충실하게 재현, 기본 배치는 시스템 순서를 따름
- 네 손가락 오므리기, 메뉴 막대 또는 Dock의 AppPad 클릭으로 열기(다시 클릭하면 닫힘)
- 폴더, 드래그로 정렬 / 폴더 만들기, 아이콘을 길게 누르거나 ⌥ 키를 누른 채로 편집 모드
- 깔끔한 제거 기능 내장: 앱과 남은 파일을 함께 삭제
- 격자 검색, 페이지 표시기(점 / 숫자), Liquid Glass 제어기(macOS 26+)
- 배경: 흰색 / 연한 회색 / 진한 회색 / 배경화면 / 사용자화 색상, 라이트·다크 모드별 개별 설정

### 클립보드
- 텍스트와 이미지를 영구 보관
- 복사한 항목을 저장 가능
- `⌘1`–`⌘0` 빠른 붙여넣기, 원본 앱 필터, `앱이름::` 검색 문법, 실시간 미리보기

### 워크플로 & AI MCP
- `⌘Space`로 워크플로 패널 열기: 앱과 워크플로를 사용 빈도에 따라 함께 정렬
- 워크플로로 셸 스크립트, AppleScript, 단축어, HTTP 요청을 실행하며 인자 지원(예: `time 10`)
- 내장: 휴지통 비우기, 타이머 설정, 알람 설정, 음량 설정, 모든 앱 종료…
- 선언된 권한을 실제 샌드박스로 강제(한 번 허용 / 허용 안 함 / 항상 허용)
- JSON 파일이나 링크로 워크플로 가져오기 및 공유
- MCP 서버 내장: MCP를 지원하는 AI 어시스턴트가 워크플로를 직접 호출하고 제어
- AI가 MCP로 워크플로 작성 규칙을 읽고 새 워크플로를 만들어 줌
- AI가 실행하는 워크플로도 직접 실행할 때와 같은 권한 확인과 샌드박스를 거침

### 계산기
- 워크플로 패널 검색 필드에 수식을 바로 입력해 계산(과학적 표기법 지원)

### 앱 단축키
- 모든 앱에 전역 단축키 지정

### 윈도우 제어
- 왼쪽 / 오른쪽에 맞추기(½ → ⅓ → ⅔), 최대화, 복원, 다른 디스플레이로 이동 — 모든 단축키 사용자 지정 가능

### 기타
- 로그인 시 실행
- `⌘⇧J` / `⌘⇧K`로 Launchpad, 클립보드, 워크플로 간 애니메이션 전환
- 10개 언어: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## 시스템 요구 사항

- macOS 15 이상
- Xcode 27(소스에서 빌드하는 경우)

## 빌드

1. `AppPad.xcodeproj` 열기
2. 스킴 선택: `AppPad Dev`, `AppPad Beta` 또는 `AppPad`
3. 자신의 서명 팀을 설정한 뒤 빌드 및 실행

의존성은 Swift Package Manager로 관리됩니다.

## 라이선스

AppPad는 분할 라이선스를 사용합니다:

| 구성 요소 | 라이선스 |
| --- | --- |
| AppPad 앱 소스 코드(아래에 나열되지 않은 모든 것) | [AGPL-3.0](../../LICENSE) |
| 내장 워크플로(`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](../../LICENSE-MIT) |
| 워크플로 형식 사양 | [MIT](../../LICENSE-MIT) |
| 워크플로 마켓의 서드파티 워크플로 | [MIT](../../LICENSE-MIT), 저작권은 각 작성자 |

- **AGPL-3.0**: AppPad를 사용·수정·재배포할 수 있지만, 배포하거나 네트워크로 제공하는 파생 저작물은 전체 소스 코드와 함께 AGPL-3.0으로 공개해야 합니다.
- **상용 라이선스**: 비공개 소스 또는 독점적 용도로 사용하려면 [웹사이트](https://apppad.youmindhub.com)를 통해 작성자에게 상용 라이선스를 문의하세요.
- **워크플로는 MIT**: 누구나 워크플로를 자유롭게 작성·공유·판매할 수 있고, 다른 도구에 워크플로 형식을 구현할 수도 있으며, AGPL 의무가 없습니다.
- 직접 만든 워크플로는 본인의 것입니다. 워크플로 마켓에 제출하는 워크플로는 MIT 라이선스여야 합니다.
- "AppPad"라는 이름과 아이콘은 이 라이선스에 포함되지 않으며, 포크는 다른 이름과 아이콘을 사용해야 합니다.

## 기여하기

이슈와 풀 리퀘스트를 환영합니다. 기여를 제출하면 해당 기여가 수정한 부분의 라이선스로 공개되는 것, 그리고 관리자가 이를 상용 라이선스로도 배포할 수 있는 권리를 부여하는 것에 동의하는 것으로 간주됩니다.

## 감사의 말

- [GRDB.swift](https://github.com/groue/GRDB.swift) — MIT 라이선스
- [Sparkle](https://github.com/sparkle-project/Sparkle) — MIT 라이선스

<a id="wechat-donate"></a>

## AppPad 후원하기

AppPad는 무료 오픈소스입니다. Mac을 조금이라도 더 편하게 쓰는 데 도움이 되었다면, WeChat으로 커피 한 잔 사 주시면 큰 힘이 됩니다. 금액은 마음 가는 대로 괜찮고, GitHub 스타도 큰 응원이 됩니다. 감사합니다!

<p align="center">
  <img src="../images/wechat-donate.png" width="300" alt="WeChat">
  <br>
  <sub>WeChat으로 스캔</sub>
</p>

---

© 2026 YouMindHub
