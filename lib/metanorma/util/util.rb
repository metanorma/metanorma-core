module Metanorma
  # Cross-cutting helpers used by the metanorma stack: logging gated by
  # {Metanorma::Configuration#logs}, ordering of output-format extensions
  # for execution, and recursive hash key normalisation.
  module Util
    class << self
      # Print +message+ to stdout if +type+ is in
      # {Metanorma::Configuration#logs}; abort the process with the
      # message on stderr if +type+ is +:fatal+.
      #
      # The +:fatal+ message is written to stderr unconditionally: a
      # fatal abort that only surfaces when the right log category is
      # configured reads as a silent death of the process
      # (metanorma/iso-10303#756).
      #
      # @param message [String] the message to print.
      # @param type [Symbol] severity, defaults to +:info+. Common
      #   values: +:info+, +:warning+, +:error+, +:fatal+. The
      #   configured +logs+ list determines which severities are
      #   printed; +:fatal+ aborts with the message on top of printing.
      # @return [void]
      def log(message, type = :info)
        log_types = Metanorma.configuration.logs.map(&:to_s) || []

        if log_types.include?(type.to_s)
          puts(message)
        end

        # Kernel#abort prints the message to stderr and exits 1.
        abort(message) if type == :fatal
      end

      # Sort key used to put output-format extensions in execution order.
      # +xml+ runs first because the semantic XML feeds everything else;
      # +rxl+ second; +presentation+ third (consumed by HTML/Word/PDF);
      # everything else last (alphabetical via the caller's sort
      # stability).
      #
      # @param ext [Symbol] output-format extension symbol.
      # @return [Integer] ordinal for sorting.
      def sort_extensions_execution_ord(ext)
        case ext
        when :xml then 0
        when :rxl then 1
        when :presentation then 2
        else
          99
        end
      end

      # Stable-sort a list of output-format extensions by execution
      # priority (see {.sort_extensions_execution_ord}).
      #
      # @param ext [Array<Symbol>] extensions to sort.
      # @return [Array<Symbol>] sorted in execution order.
      def sort_extensions_execution(ext)
        ext.sort do |a, b|
          sort_extensions_execution_ord(a) <=> sort_extensions_execution_ord(b)
        end
      end

      # Recursively normalise the keys of a Hash (and any nested Hashes
      # / Enumerables) to Strings. Used to canonicalise YAML/JSON-derived
      # configuration that may have been parsed with mixed symbol /
      # string keys.
      #
      # @param hash [Hash, Enumerable, Object] the value to normalise.
      # @return [Hash, Array, Object] the normalised value; non-collections
      #   are returned unchanged.
      def recursive_string_keys(hash)
        case hash
        when Hash then hash.map do |k, v|
                         [k.to_s, recursive_string_keys(v)]
                       end.to_h
        when Enumerable then hash.map { |v| recursive_string_keys(v) }
        else
          hash
        end
      end
    end
  end
end
