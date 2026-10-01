module Nerv
  class CLI
    def self.start(arguments, workspace_root:)
      new(arguments, workspace_root:).run
    end

    def initialize(arguments, workspace_root:)
      @arguments = arguments
      @workspace_root = workspace_root
    end

    def run
      if @arguments.first == "init"
        setup = File.join(@workspace_root, "setup.sh")
        unless system(setup, "--workspace-only")
          warn "nerv init: workspace configuration failed"
          return 1
        end
        return MemoryService.new(@workspace_root).run(["init", *@arguments.drop(1)])
      end

      if ["mcp-memory-service", "knowledge-graph"].include?(@arguments.first)
        return MemoryService.new(@workspace_root).run(@arguments.drop(1))
      end

      if @arguments.empty? || @arguments == ["--help"] || @arguments == ["-h"]
        puts <<~HELP
          Usage: bin/nerv <command> [options]

          NERV workspace agent tooling.

          Commands:
            init                Configure workspace defaults and initialize mcp-memory-service
            mcp-memory-service  Set up and manage the local service (alias: knowledge-graph)
        HELP
        return 0
      end

      warn "nerv: command not implemented: #{@arguments.join(' ')}"
      2
    end
  end
end
