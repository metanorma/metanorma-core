# frozen_string_literal: true

require "date"

module Metanorma
  module Core
    # Locate and load the right flavor gem (e.g. +metanorma-iso+,
    # +metanorma-itu+) for a given standard type, registering its
    # processor with {Metanorma::Registry} as a side effect.
    #
    # Standard types may be specified as a "taste" name
    # (e.g. +:bipm+, +:icc+) which is mapped to its canonical flavor
    # via {Metanorma::TasteRegister}. Flavor gems follow the
    # +metanorma-<flavor>+ naming convention.
    #
    # The +load_flavor+ entry point both resolves and loads, and is
    # idempotent: if the flavor's processor is already registered,
    # no gem load is attempted.
    module FlavorLoader
      module_function

      # Resolve a standard type or taste name to its canonical flavor
      # symbol via the TasteRegister.
      #
      # @param stdtype [Symbol, String] standard type or taste name.
      # @return [Symbol] canonical flavor symbol (the input if no
      #   taste alias matched).
      def taste2flavor(stdtype)
        stdtype = stdtype.to_sym
        tastes = Metanorma::TasteRegister.instance.aliases
        tastes[stdtype] and stdtype = tastes[stdtype].to_sym
        stdtype
      end

      # Map a canonical flavor symbol to its gem name.
      #
      # @param stdtype [Symbol, String] canonical flavor symbol.
      # @return [String] gem name (e.g. +"metanorma-iso"+).
      def stdtype2flavor_gem(stdtype)
        "metanorma-#{stdtype}"
      end

      # Load the flavor gem for +stdtype+ if its processor is not yet
      # registered, and return the canonical flavor symbol.
      #
      # On a fatal LoadError, an error log file is written and
      # +abort+ is called via {Metanorma::Util#log} (severity +:fatal+).
      # If the gem loads but does not register a processor under the
      # expected canonical name, the same fatal-abort path runs.
      #
      # @param stdtype [Symbol, String] standard type or taste name.
      # @return [Symbol] canonical flavor symbol.
      def load_flavor(stdtype)
        canonical = taste2flavor(stdtype)
        gem_name = stdtype2flavor_gem(canonical)
        registry = Metanorma::Registry.instance
        registry.supported_backends.include?(canonical) or
          require_flavor_gem(gem_name, stdtype)
        registry.supported_backends.include?(canonical) or
          flavor_unsupported(gem_name, stdtype)
        canonical
      end

      # Require the flavor gem and log success / failure. On +LoadError+,
      # delegates to {.write_flavor_error_log} which produces a fatal
      # abort. Used internally by {.load_flavor}.
      #
      # @param gem_name [String] gem name (e.g. +"metanorma-iso"+).
      # @param stdtype [Symbol, String] standard type for the user-facing
      #   info log line.
      def require_flavor_gem(gem_name, stdtype)
        Metanorma::Util.log("[metanorma] Info: Loading `#{gem_name}` gem " \
                            "for standard type `#{stdtype}`.", :info)
        require gem_name
        Metanorma::Util.log("[metanorma] Info: gem `#{gem_name}` loaded.",
                            :info)
      rescue LoadError => e
        write_flavor_error_log(e, gem_name)
      end

      # Write a dated error-log file capturing a failed gem load and
      # abort with a user-facing fatal message that points the user at
      # the metanorma issue tracker.
      #
      # @param err [Exception] the LoadError raised by +require+.
      # @param gem_name [String] gem name that failed to load.
      # @return [void] (calls +abort+ via {Metanorma::Util#log}).
      def write_flavor_error_log(err, gem_name)
        error_log = "#{Date.today}-error.log"
        File.write(error_log, err)
        msg = <<~MSG
          Error: #{err.message}
          Metanorma has encountered an exception.

          If this problem persists, please report this issue at the following link:

          * https://github.com/metanorma/metanorma/issues/new

          Please attach the #{error_log} file.
          Your valuable feedback is very much appreciated!

          - The Metanorma team
        MSG
        Metanorma::Util.log(msg, :fatal)
      end

      # Fatal-abort path for the case where the flavor gem loaded but
      # did not register a processor for the requested standard type.
      #
      # @param gem_name [String] gem name that loaded.
      # @param stdtype [Symbol, String] standard type that the gem did
      #   not register a processor for.
      # @return [void] (calls +abort+ via {Metanorma::Util#log}).
      def flavor_unsupported(gem_name, stdtype)
        Metanorma::Util.log("[metanorma] Error: The `#{gem_name}` gem does " \
                            "not support the standard type #{stdtype}. " \
                            "Exiting.", :fatal)
      end
    end
  end
end
