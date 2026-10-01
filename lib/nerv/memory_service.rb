require "open3"
require "json"

module Nerv
  class MemoryService
    SERVER_NAME = "mcp-memory-service"
    BACKEND = "sqlite_vec"
    HOST = "127.0.0.1"
    PORT = "8000"
    LOCAL_SERVICE_ENV = {
      "MCP_MEMORY_STORAGE_BACKEND" => BACKEND,
      "MCP_ALLOW_ANONYMOUS_ACCESS" => "true"
    }.freeze

    def initialize(workspace_root)
      @workspace_root = workspace_root
      @memory_dir = File.join(workspace_root, "external", SERVER_NAME)
      @memory = File.join(@memory_dir, ".venv", "bin", "memory")
    end

    def run(arguments)
      command = arguments.first || "help"
      case command
      when "init"
        initialize_if_needed
      when "setup"
        return 1 unless ensure_installed

        start_server && register_clients
      when "start"
        return 1 unless ensure_installed

        start_server
      when "stop"
        run_memory("stop")
      when "status"
        run_memory("info")
      when "register"
        return 1 unless ensure_installed

        register_clients
      when "help", "--help", "-h"
        print_help
        0
      else
        warn "nerv mcp-memory-service: unknown command: #{command}"
        print_help
        2
      end
    end

    private

    def initialize_if_needed
      return 1 unless ensure_installed

      status_ok = run(["status"])
      healthy = service_healthy?
      if healthy
        if status_ok
          puts "mcp-memory-service가 이미 실행 중입니다."
        else
          warn "status 명령은 실패했지만 health endpoint가 응답해 실행 중으로 판단합니다."
        end
      else
        puts "mcp-memory-service가 실행 중이 아니어서 시작합니다."
        return 1 unless start_server
      end

      return 1 unless run(["register"])

      0
    end

    def service_healthy?
      require "net/http"
      require "uri"

      response = Net::HTTP.start(HOST, PORT, open_timeout: 1, read_timeout: 1) do |http|
        http.get("/api/health")
      end
      response.is_a?(Net::HTTPSuccess)
    rescue IOError, SystemCallError, Timeout::Error, SocketError
      false
    end

    def ensure_installed
      unless File.executable?(@memory)
        warn "mcp-memory-service is not installed. Run ./setup.sh first."
        return false
      end

      python = File.join(@memory_dir, ".venv", "bin", "python")
      dependencies_installed = system(
        python,
        "-c",
        'import importlib.util, sys; sys.exit(0 if all(importlib.util.find_spec(name) for name in ("torch", "sentence_transformers", "onnxruntime")) else 1)',
        out: File::NULL,
        err: File::NULL
      )
      unless dependencies_installed
        puts "SQLite-vec 의미 검색 의존성을 설치합니다 (torch, sentence-transformers, ONNX Runtime)."
        return false unless run_external(python, "-m", "pip", "install", "--editable", "#{@memory_dir}[sqlite-ml]")
      end

      true
    end

    def start_server
      return false unless run_memory(
        "launch",
        "--storage-backend", BACKEND,
        "--host", HOST,
        "--port", PORT,
        env: LOCAL_SERVICE_ENV
      )

      puts "대시보드: http://#{HOST}:#{PORT}/"
      puts "REST API health: http://#{HOST}:#{PORT}/api/health"
      true
    end

    def register_clients
      command = [@memory, "server"]
      codex_ok = register_one("Codex", "codex", ["mcp", "get", SERVER_NAME, "--json"], command) do
        run_external(
          "codex", "mcp", "add", SERVER_NAME,
          "--env", "MCP_MEMORY_STORAGE_BACKEND=#{BACKEND}",
          "--", *command
        )
      end
      claude_ok = register_one("Claude Code", "claude", ["mcp", "get", SERVER_NAME], command) do
        run_external(
          "claude", "mcp", "add", SERVER_NAME, "--scope", "user",
          "--env", "MCP_MEMORY_STORAGE_BACKEND=#{BACKEND}",
          "--", *command
        )
      end

      active_clients = ["codex", "claude"].select { |client| executable_available?(client) }
      if codex_ok && claude_ok && !active_clients.empty?
        remove_legacy_registration(
          "Codex", ["codex", "mcp", "get", "knowledge-graph", "--json"],
          ["codex", "mcp", "remove", "knowledge-graph"]
        )
        remove_legacy_registration(
          "Claude Code", ["claude", "mcp", "get", "knowledge-graph"],
          ["claude", "mcp", "remove", "--scope", "user", "knowledge-graph"]
        )
        puts "#{active_clients.map { |client| client == 'codex' ? 'Codex' : 'Claude Code' }.join('와 ')}에 사용자 범위 MCP '#{SERVER_NAME}'을 확인했습니다."
        true
      else
        warn "MCP 등록이 일부 실패했습니다. codex mcp list와 claude mcp list로 확인하세요."
        false
      end
    end

    def run_memory(*arguments)
      command = [@memory, *arguments]
      unless File.executable?(@memory)
        warn "필수 실행 파일을 찾을 수 없습니다: #{@memory}"
        return false
      end

      system(LOCAL_SERVICE_ENV, @memory, *arguments)
    end

    def register_one(label, executable, check_arguments, expected_command)
      unless executable_available?(executable)
        puts "#{label}: CLI가 없어 MCP 등록 확인을 건너뜁니다."
        return true
      end

      stdout, stderr, status = Open3.capture3(executable, *check_arguments)
      details = stdout.empty? ? stderr : stdout
      if status.success?
        if valid_registration?(executable, details, expected_command)
          puts "#{label}: MCP '#{SERVER_NAME}' 설정이 올바릅니다."
          return true
        end

        warn "#{label}: MCP '#{SERVER_NAME}' 등록이 있지만 실행 경로나 backend가 다릅니다. 기존 설정을 보존했습니다."
        return false
      end

      if missing_registration?(details)
        yield
      else
        warn "#{label}: MCP 등록 조회에 실패했습니다: #{details.strip}"
        false
      end
    end

    def valid_registration?(executable, details, expected_command)
      if executable == "codex"
        config = JSON.parse(details)
        transport = config.fetch("transport")
        transport.fetch("command") == expected_command.first &&
          transport.fetch("args") == expected_command.drop(1) &&
          transport.fetch("env").fetch("MCP_MEMORY_STORAGE_BACKEND") == BACKEND
      else
        command = details[/^\s*Command:\s*(.+)$/, 1]&.strip
        arguments = details[/^\s*Args:\s*(.*)$/, 1]&.strip
        backend = details[/^\s*MCP_MEMORY_STORAGE_BACKEND=(.+)$/, 1]&.strip
        command == expected_command.first &&
          arguments == expected_command.drop(1).join(" ") &&
          backend == BACKEND
      end
    rescue JSON::ParserError, KeyError, TypeError
      false
    end

    def missing_registration?(details)
      details.match?(/No MCP server named ['\"]?#{Regexp.escape(SERVER_NAME)}['\"]?/i) ||
        details.match?(/MCP server ['\"]?#{Regexp.escape(SERVER_NAME)}['\"]? not found/i)
    end

    def remove_legacy_registration(label, check_command, remove_command)
      return unless executable_available?(check_command.first)

      details, status = Open3.capture2e(*check_command)
      return unless status.success?

      unless details.include?(@memory) && details.include?("server")
        warn "#{label}: 기존 'knowledge-graph' MCP가 다른 설정이라 보존했습니다."
        return
      end

      if run_external(*remove_command)
        puts "#{label}: 이전 'knowledge-graph' MCP 별칭 등록을 정리했습니다."
      end
    end

    def run_external(*command)
      unless executable_available?(command.first)
        warn "필수 실행 파일을 찾을 수 없습니다: #{command.first}"
        return false
      end

      system(*command)
    end

    def executable_available?(executable)
      return File.executable?(executable) if executable.include?(File::SEPARATOR)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, executable))
      end
    end

    def print_help
      puts <<~HELP
        Usage: bin/nerv mcp-memory-service <command>
               bin/nerv knowledge-graph <command>  (alias)
               bin/nerv init

        Commands:
          init      Check service status and register MCP for installed Codex/Claude CLIs
          setup     Start the local dashboard/REST service and register MCP for Codex and Claude Code
          start     Start the local dashboard/REST service
          stop      Stop the local dashboard/REST service
          status    Show the local dashboard/REST service status
          register  Register the stdio MCP server for Codex and Claude Code
      HELP
    end
  end
end
