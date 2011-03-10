require "json"
require "tempfile"

module ExecJS
  class ExternalRuntime
    class Context
      def initialize(runtime, source = "")
        @runtime = runtime
        @source  = source
      end

      def eval(source, options = {})
        if /\S/ =~ source
          exec("return eval(#{"(#{source})".to_json})")
        end
      end

      def exec(source, options = {})
        compile_to_tempfile([@source, source].join("\n")) do |file|
          extract_result(@runtime.send(:exec_runtime, file.path))
        end
      end

      def call(properties, *args)
        eval "#{properties}.apply(this, #{args.to_json})"
      end

      protected
        def compile_to_tempfile(source)
          tempfile = Tempfile.open("execjs")
          tempfile.write compile(source)
          tempfile.close
          yield tempfile
        ensure
          tempfile.close!
        end

        def compile(source)
          @runtime.send(:runner_source).dup.tap do |output|
            output.sub!('#{source}') do
              source
            end
            output.sub!('#{json2_source}') do
              IO.read(ExecJS.root + "/support/json2.js")
            end
          end
        end

        def extract_result(output)
          status, value = output.empty? ? [] : JSON.parse(output)
          if status == "ok"
            value
          else
            raise ProgramError, value
          end
        end
    end

    attr_reader :name

    def initialize(options)
      @name        = options[:name]
      @command     = options[:command]
      @runner_path = options[:runner_path]
      @test_args   = options[:test_args]
      @test_match  = options[:test_match]
      @conversion  = options[:conversion]
      @binary      = locate_binary
    end

    def exec(source)
      context = Context.new(self)
      context.exec(source)
    end

    def eval(source)
      context = Context.new(self)
      context.eval(source)
    end

    def compile(source)
      Context.new(self, source)
    end

    def available?
      @binary ? true : false
    end

    protected
      def runner_source
        @runner_source ||= IO.read(@runner_path)
      end

      def exec_runtime(filename)
        output = sh("#{@binary} #{filename} 2>&1")
        if $?.success?
          output
        else
          raise RuntimeError, output
        end
      end

      def locate_binary
        if binary = which(@command)
          if @test_args
            output = `#{binary} #{@test_args} 2>&1`
            binary if output.match(@test_match)
          else
            binary
          end
        end
      end

      def which(command)
        Array(command).find do |name|
          name = name.split(/\s+/).first
          result = if ExecJS.windows?
            `#{ExecJS.root}/support/which.bat #{name}`
          else
            `which #{name} 2>&1`
          end
          result.strip.split("\n").first
        end
      end

      if "".respond_to?(:force_encoding)
        def sh(command)
          output, options = nil, {}
          options[:internal_encoding] = @conversion[:from] if @conversion
          IO.popen(command, options) { |f| output = f.read }
          output.force_encoding(@conversion[:to]) if @conversion
          output
        end
      else
        require "iconv"

        def sh(command)
          output = nil
          IO.popen(command) { |f| output = f.read }

          if @conversion
            Iconv.iconv(@conversion[:from], @conversion[:to], output).first
          else
            output
          end
        end
      end
  end
end