# frozen_string_literal: true

require "date"

module Metanorma
  module Core
    module FlavorLoader
      module_function

      def taste2flavor(stdtype)
        stdtype = stdtype.to_sym
        tastes = Metanorma::TasteRegister.instance.aliases
        tastes[stdtype] and stdtype = tastes[stdtype].to_sym
        stdtype
      end

      def stdtype2flavor_gem(stdtype)
        "metanorma-#{stdtype}"
      end

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

      def require_flavor_gem(gem_name, stdtype)
        Metanorma::Util.log("[metanorma] Info: Loading `#{gem_name}` gem " \
                            "for standard type `#{stdtype}`.", :info)
        require gem_name
        Metanorma::Util.log("[metanorma] Info: gem `#{gem_name}` loaded.",
                            :info)
      rescue LoadError => e
        write_flavor_error_log(e, gem_name)
      end

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

      def flavor_unsupported(gem_name, stdtype)
        Metanorma::Util.log("[metanorma] Error: The `#{gem_name}` gem does " \
                            "not support the standard type #{stdtype}. " \
                            "Exiting.", :fatal)
      end
    end
  end
end
