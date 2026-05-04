module Metanorma
  # Configuration mixin for the +Metanorma+ module. Provides the
  # +Metanorma.configure+ block-based setup pattern and the
  # +Metanorma.configuration+ accessor for read access.
  #
  # @example
  #   Metanorma.configure do |c|
  #     c.logs = %i[error fatal]
  #   end
  module Config
    # Yield the singleton {Metanorma::Configuration} for in-place
    # mutation, e.g. flipping which log severities are printed.
    #
    # @yieldparam [Metanorma::Configuration] the singleton config.
    # @return [Metanorma::Configuration, nil] the config if no block
    #   was given (preserving the original semantics), otherwise the
    #   block's return value.
    def configure
      if block_given?
        yield configuration
      end
    end

    # Lazily-instantiated singleton {Metanorma::Configuration} for the
    # +Metanorma+ module.
    #
    # @return [Metanorma::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end
  end

  # Mutable runtime configuration for the metanorma stack. Currently
  # carries only the +logs+ severity allowlist consumed by
  # {Metanorma::Util#log}; other settings can be added here as
  # cross-cutting needs arise.
  class Configuration
    # @return [Array<Symbol>] severities printed by {Metanorma::Util#log}.
    attr_accessor :logs

    def initialize
      @logs = %i[warning error fatal]
    end
  end

  extend Config
end
