# NERV workspace

이 workspace 자체가 NERV 최상위 프로젝트다. Ruby CLI 진입점은 `bin/nerv`, 구현은
`lib/nerv/`에 둔다. CLI는 자신의 경로를 기준으로 workspace를 찾으므로 다른 현재
디렉터리에서도 같은 workspace를 대상으로 실행한다. gem 패키징과 의존성이 필요해질
때 `nerv.gemspec`과 `Gemfile`을 추가한다.

로컬 `mcp-memory-service`와 Codex·Claude MCP 등록은 `bin/nerv mcp-memory-service setup`으로
실행한다. `knowledge-graph`는 CLI의 별칭이다. `start`, `stop`, `status`, `register` 하위 명령도 제공한다. 대시보드와 REST API는
localhost의 port 8000에서 동작하며 로컬 전용 익명 접근을 허용한다. Codex·Claude는 같은 SQLite-vec 저장소를 사용하는
stdio MCP 서버를 사용자 설정에 등록한다. `AGENTS.local.md`는 Knowledge Graph·MCP Memory·지식 그래프를 서비스 별칭으로 인식하도록 안내한다.
`bin/nerv init`은 workspace 기본 구성을 확인하고, mcp-memory-service 설치·상태를 점검해 실행 중이 아니면 시작한다. 설치된 Codex·Claude CLI의 사용자 범위 MCP 등록만 확인하며, 등록이 없으면 추가한다. 기존 등록의 실행 경로나 backend가 다르면 덮어쓰지 않고 오류로 알린다.

공통 운영 지침은 [AGENTS.md](AGENTS.md)에 둔다. Codex 설정은 `.codex/`, Claude Code
설정은 `.claude/`에서 관리하며 `CLAUDE.md`가 공통 지침을 import한다. 개인 규칙은
Git에서 제외되는 `AGENTS.local.md`에 적어 공통 지침을 덮어쓸 수 있다.

## 초기 구성

```sh
./bootstrap.sh
./setup.sh
bin/nerv init
```

`setup.sh`에 기본 파일 내용과 생성 로직을 모두 포함한다. workspace 설정 단계는
macOS 기본 Bash와 시스템 명령만 사용한다. 외부 메모리 서비스 설치에는 Python venv를 사용한다.
Codex CLI와 Claude Code는 각 제공자의 공식 installer를 사용해 설치한다. setup은
특정 CLI 버전을 고정하지 않으며, 이미 설치된 CLI는 재설치하지 않는다. 업데이트는
각 installer와 CLI의 기본 동작에 맡긴다.

- `--workspace-only`: 없는 workspace 폴더·파일만 생성한다. 설치나 사용자 홈 변경은 없다.
- `--skip-install`: CLI와 mcp-memory-service 설치를 생략한다.
- `--check`: 변경 없이 기본 파일·폴더, JSON/TOML 문법, MAGI 설명의 harness 간 일치,
  setup 기본값과 로컬 설정 차이, 셸 문법을 검사한다. 차이는 표시만 하며 덮어쓰지 않는다.

일반 `setup.sh` 실행은 `external/mcp-memory-service/`가 없으면 upstream 저장소를
clone하고, 저장소 안 `.venv`에 `[sqlite-ml]` extra와 함께 editable 설치한다. 이 extra는
SQLite-vec와 semantic search용 `torch`, `sentence-transformers`, ONNX Runtime을 제공한다.
기존 checkout은 pull하지 않는다.
`bin/nerv mcp-memory-service start`는 SQLite-vec와 `MCP_ALLOW_ANONYMOUS_ACCESS=true`를 지정해
로컬 서버를 시작한다. 서버는 `127.0.0.1`에만 바인딩되며 외부 네트워크에 노출하지 않는다.
`setup.sh`는 CLI와 메모리 서비스를 설치하지만 서버를 자동 실행하거나 Codex·Claude MCP 설정을 변경하지 않는다.
설치가 끝난 뒤 `bin/nerv init`을 실행하면 workspace 기본 구성을 확인하고, 메모리 서비스 상태를 점검해
필요하면 시작한 다음 설치된 Codex·Claude CLI에 MCP 서버를 등록한다.

기존 파일은 내용과 권한을 보존한다. 기존 JSON·TOML에 누락된 키를 자동 병합하지
않으므로, 설정 변경은 해당 파일에서 직접 관리한다. `--check`는 설정 형식 전체나
모델 유효성을 검증하는 doctor가 아니다.

Git에는 `AGENTS.md`, `CLAUDE.md`, `README.md`, `setup.sh`, `bootstrap.sh`, `.gitignore`와
프로젝트·외부 저장소 폴더의 `.gitkeep`을 관리한다. setup이 생성하는 `.codex/`,
`.claude/`, `.mcp.json`, `.agentignore`, `CLAUDE.local.md`와 개인 메모리는 로컬 전용으로
제외한다. 공용 기본값 변경은 `setup.sh`에서 관리하고, 생성된 파일은 개인 환경에
맞게 수정한다. `projects/`와 `external/` 아래 실제 저장소는 별도 Git으로 관리한다.

- `projects/`: 프로젝트별 코드와 독립 Git 저장소.
- `external/`: 외부 독립 저장소. 기본 setup은 `mcp-memory-service`를 clone하고 저장소 내부 `.venv`에 설치한다.
- `memory/GLOBAL.md`: 전역 메모리. 프로젝트 메모리와 분리한다.
- `.mcp.json`: Claude MCP 등록. 초기 등록은 없으며 Codex에도 MCP를 등록하지 않는다.

기본 Codex 모델은 `gpt-6-luna / low`, MAGI는 `gpt-6-astra / xhigh`다.
Claude MAGI는 `fable`을 사용한다. 기존 세션의 모델은 setup만으로 변경되지 않는다.

추가 실행·관리 기능은 별도 addon에서 제공한다. 기본 workspace setup은 tmux
세션·pane을 조작하지 않는다.

## CLI 설치

`setup.sh`는 Codex와 Claude Code가 PATH에서 검색되지 않을 때 각 제공자의 공식
installer를 실행한다. 설정에는 정확한 CLI 버전이나 Homebrew 패키지 버전이 없다.

## 검증

```sh
./setup.sh --check
bash -n setup.sh bootstrap.sh
```
