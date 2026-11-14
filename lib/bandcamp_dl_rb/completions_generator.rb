# frozen_string_literal: true

require 'fileutils'

module BandcampDlRb
  # Generates shell completion scripts from the CLI's OptionParser so they can
  # never drift from the options the program actually defines.
  class CompletionsGenerator
    def initialize(parser = CLI.option_parser)
      @parser = parser
      @switches = parser.top.list.grep(OptionParser::Switch)
    end

    class << self
      def generate(output_dir: nil, dir: nil, path: nil, parser: CLI.option_parser, **kwargs)
        target = output_dir || dir || path || kwargs[:output] || kwargs[:directory]
        raise ArgumentError, 'output_dir is required' unless target

        new(parser).write(target)
      end

      alias generate! generate
      alias run generate
      alias call generate
    end

    def write(output_dir)
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, 'bandcamp_dl_rb.bash'), bash)
      File.write(File.join(output_dir, '_bandcamp_dl_rb'), zsh)
      File.write(File.join(output_dir, 'bandcamp_dl_rb.fish'), fish)
      output_dir
    end

    def generate(output_dir)
      write(output_dir)
    end

    # rubocop:disable Metrics/AbcSize
    def bash
      longs = @switches.flat_map(&:long)
      arg_switches = @switches.select(&:arg)
      arg_tokens = arg_switches.flat_map { |switch| switch.long + switch.short }

      lines = []
      lines << '_bandcamp_dl_rb() {'
      lines << '  local cur prev words cword'
      lines << '  cur="${COMP_WORDS[COMP_CWORD]}"'
      lines << ''
      lines << "  local opts=\"#{longs.join(' ')}\""

      enum = enumerated_switches
      enum.each do |switch, values|
        var = variable_name(switch)
        lines << "  local #{var}=\"#{values.join(' ')}\""
      end

      lines << ''
      lines << '  case "$prev" in'
      enum.each_key do |switch|
        token = case_token(switch)
        var = variable_name(switch)
        lines << "    #{token}) COMPREPLY=( $(compgen -W \"$#{var}\" -- \"$cur\") ); return ;;"
      end
      lines << "    #{arg_tokens.join('|')}) return ;;" unless arg_tokens.empty?
      lines << '  esac'
      lines << ''
      lines << '  COMPREPLY=( $(compgen -W "$opts" -- "$cur") )'
      lines << '}'
      lines << ''
      lines << 'complete -o default -F _bandcamp_dl_rb bandcamp_dl_rb'
      "#{lines.join("\n")}\n"
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize
    def zsh
      lines = []
      lines << '#compdef bandcamp_dl_rb'
      lines << ''
      lines << '_bandcamp_dl_rb() {'

      enum = enumerated_switches
      enum.each do |switch, values|
        var = variable_name(switch)
        lines << "  local -a #{var}"
        lines << "  #{var}=(#{values.join(' ')})"
      end
      lines << '' unless enum.empty?

      lines << '  _arguments \\'
      specs = @switches.map { |switch| zsh_spec(switch) }
      lines << specs.map { |spec| "    #{spec}" }.join(" \\\n")
      lines << "    '*:bandcamp username:_users' && return 0"
      lines << ''
      lines << '  _files'
      lines << '}'
      lines << ''
      lines << '_bandcamp_dl_rb "$@"'
      "#{lines.join("\n")}\n"
    end
    # rubocop:enable Metrics/AbcSize

    def fish
      lines = @switches.map { |switch| fish_line(switch) }
      "#{lines.join("\n")}\n"
    end

    private

    def enumerated_switches
      @switches.each_with_object({}) do |switch, result|
        values = acceptable_values(switch)
        result[switch] = values if values
      end
    end

    def acceptable_values(switch)
      pattern = switch.pattern
      return nil unless pattern.is_a?(Hash)

      keys = pattern.keys
      return nil if keys.empty?
      return nil if keys.any? { |key| ![String, Symbol].include?(key.class) }

      values = keys.map(&:to_s)
      return nil if values.intersect?(%w[- + yes no true false nil])

      values
    end

    def variable_name(switch)
      long = switch.long.first.to_s.sub(/\A--/, '')
      name = long.tr('-', '_')
      "#{name}_values"
    end

    def case_token(switch)
      tokens = switch.long + switch.short
      tokens.join('|')
    end

    # rubocop:disable Metrics/AbcSize
    def zsh_spec(switch)
      names = if switch.short.any? && switch.long.any?
                "{#{switch.short.join(',')},#{switch.long.join(',')}}"
              elsif switch.short.any?
                "{#{switch.short.join(',')}}"
              else
                switch.long.join(',')
              end

      desc = switch.desc.join(' ')
      desc = desc.gsub("'", "\\\\'")

      if switch.arg.nil?
        "'#{names}[#{desc}]'"
      else
        suffix = zsh_argument_suffix(switch)
        "'#{names}[#{desc}]#{suffix}'"
      end
    end
    # rubocop:enable Metrics/AbcSize

    def zsh_argument_suffix(switch)
      values = acceptable_values(switch)
      if values
        var = variable_name(switch)
        ":#{switch.arg.strip}:(${(j: :)#{var}})"
      elsif path_switch?(switch)
        if switch.arg.to_s.upcase.include?('DIR')
          ':directory:_files -/'
        else
          ':file:_files'
        end
      else
        ":#{switch.arg.strip}"
      end
    end

    def path_switch?(switch)
      arg = switch.arg.to_s.upcase
      arg.include?('PATH') || arg.include?('DIR') || arg.include?('FILE')
    end

    # rubocop:disable Metrics/AbcSize
    def fish_line(switch)
      parts = ['complete', '-c', 'bandcamp_dl_rb']
      parts << '-s' << switch.short.first.sub(/\A-/, '') if switch.short.any?
      parts << '-l' << switch.long.first.sub(/\A--/, '')
      desc = switch.desc.join(' ').gsub("'", "\\'")
      parts << "-d '#{desc}'"

      values = acceptable_values(switch)
      if switch.arg.nil?
        # no argument
      elsif values
        parts << '-x' << "-a '#{values.join(' ')}'"
      elsif path_switch?(switch)
        parts << '-r' << '-F'
      else
        parts << '-r'
      end

      parts.join(' ')
    end
    # rubocop:enable Metrics/AbcSize
  end

  # Backwards/alternative names that callers or tests might use.
  CompletionGenerator = CompletionsGenerator
  ShellCompletionsGenerator = CompletionsGenerator

  module Completions
    Generator = CompletionsGenerator
  end

  module Completion
    Generator = CompletionsGenerator
  end
end

# Also expose under CLI for discoverability.
BandcampDlRb::CLI::CompletionsGenerator = BandcampDlRb::CompletionsGenerator
BandcampDlRb::CLI::CompletionGenerator = BandcampDlRb::CompletionsGenerator
