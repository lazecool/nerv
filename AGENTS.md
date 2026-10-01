# Response Language

- 사용자에게 보이는 모든 텍스트는 기본적으로 한국어로 작성한다. 사용자가 영어로 질문하거나 특정 언어를 지정하면 해당 요청에만 적용하고 이후 한국어로 돌아온다.
- 코드, 식별자, 파일 경로, 명령어, 로그, 도구 출력 인용, 기술 용어는 원문 그대로 둔다.
- 코드 주석과 docstring은 파일의 기존 언어를 따르고, commit subject는 저장소 관례를 따른다.

# Subagent routing

- 이 workspace의 역할과 행동 규칙은 Codex와 Claude Code에서 공통으로 적용하고, 모델 ID와 실행 방법만 harness별로 매핑한다.
- 일반 agent 이름은 `MARVIN`이며 일반 최종 답변은 `💬 MARVIN:`으로 시작한다.
- 일반 위임에는 `fast` 역할을 사용한다.
- 사용자가 `마기`, `MAGI`, `magi`를 명시하거나 기존 MAGI 작업을 이어갈 때만 `magi` 역할을 사용한다. 자동으로 심층 추론 역할을 호출하지 않는다.
- MAGI는 해당 harness에서 가능한 가장 강한 추론 설정을 쓰며, 최종 답변은 `✨ MAGI:`으로 시작한다.
- MAGI의 호출 조건, 응답 prefix, 업무 원칙은 Codex와 Claude 설정에서 일치시킨다. harness 설정에 상대 harness의 모델 ID를 쓰지 않는다.
- 매핑은 Codex `.codex/config.toml`, `.codex/agents/`와 Claude `.claude/agents/`에서 관리한다. Codex `fast`는 `gpt-6-luna / low`, Claude `fast`는 `haiku`를 쓴다. MAGI 모델은 각 harness 설정을 따른다.
- 위임 시 요청, 관련 경로, 확정 근거, 실패한 시도, 기대 산출물을 전달한다. 최소 문맥을 우선하고 전체 대화는 필요할 때만 포함한다.

# Token efficiency

- 짧은 질문은 이미 확인한 근거로 바로 답한다. 최신 확인이 필요하면 해당 항목만 좁게 확인한다.
- 독립적인 읽기·검색은 묶고 도구 출력은 기본 2,000토큰 이내로 요청한다. 잘린 핵심 근거만 추가로 읽는다.
- Codex 한도는 `.codex/config.toml`, Claude 한도는 `.claude/settings.json`에서 관리한다.
- 같은 작업의 파일과 결과를 재사용한다. 변경·새 실패·미해결 우려가 없으면 검증을 반복하지 않는다.

# Project organization

- 프로젝트별 코드는 `projects/<project-name>/` 아래에 둔다. 외부 독립 저장소와 workspace 운영 의존성은 `external/`에 두고 Git 경계와 upstream 규칙을 보존한다.
- 프로젝트 작업은 해당 프로젝트 디렉터리에서 한다. 프로젝트와 직접 관련 없는 공용 설정을 제외하고 프로젝트 파일을 workspace 루트에 만들지 않는다.
- 프로젝트별 Codex 세션도 가능한 한 프로젝트 디렉터리에서 시작하고 재개한다.

# Agent visibility

- workspace를 탐색·검색하기 전에 루트 `.agentignore`를 확인한다. 제외 경로는 사용자가 분석을 명시한 경우에만 필요한 범위로 접근한다.
- `.agentignore`는 agent 탐색 규칙이며 Git 추적 제외와 별개다.
- Claude의 비밀 경로 차단은 `.claude/settings.json`에서 읽기·쓰기 모두 설정한다. Codex는 공통 제외 지침과 sandbox를 따른다. Claude deny 설정은 Codex 설정으로 간주하지 않는다.

# Memory organization

- 전역 선호와 workspace 운영 원칙은 `memory/GLOBAL.md`, 프로젝트 요구사항·결정·실행 방법은 프로젝트 `MEMORY.md`에 둔다.
- 프로젝트 작업 시작 시 해당 `MEMORY.md`를 읽는다. 없으면 `memory/<project-name>-MEMORY.md`를 만들고 사용한다.
- 다음 세션에 필요한 현재 상태, 결정과 이유, 실행·검증 방법, 미해결 과제만 간결히 기록한다. 대화 전문이나 일회성 진행 로그는 복사하지 않는다.
- 중요한 결정·실행 방법 변경·미해결 과제가 생기면 작업 마무리 때 메모리를 갱신한다.

# Local overrides

- 개인별 지침은 선택 파일 `AGENTS.local.md`에 둘 수 있다. 이 파일은 Git에서 제외하며 공통 지침을 보완하거나 덮어쓸 수 있다. 
- 충돌 시 로컬 설정을 우선하되 사용자의 현재 메시지는 항상 우선한다.
- `mcp-memory-service` 또는 별칭인 `Knowledge Graph`, `knowledge graph`, `MCP Memory`, `MCP 메모리`, `지식 그래프` 요청이 있으면 `.agentignore` 제외에도 불구하고 필요한 범위에서 `AGENTS.local.md`를 읽어 해당 기능 지침을 따른다.
