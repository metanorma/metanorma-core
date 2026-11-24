# frozen_string_literal: true

module Metanorma
  module Core
    # The process-wide flavor/taste table. Resolution walks
    # most-specific-first (tastes before their base flavors) so flavor
    # gems win over the harness defaults and taste entries fall through
    # to their base chain by yielding nil, independent of the order in
    # which the gems happened to load.
    class FlavorRegistry
      include Enumerable

      def initialize
        @flavors = []
      end

      def register(flavor)
        @flavors << flavor
        self
      end

      def each(&) = @flavors.each(&)

      def find_by_name(name)
        @flavors.reverse_each.find { |f| f.name == name.to_sym }
      end

      def flavor_for(document)
        most_specific_first.find { |f| f.matches?(document.class, document) }
      end

      # Renderer class for (document, format): walk matching entries
      # most-specific-first; a taste without its own renderer for the
      # format yields nil and falls through to the base flavor entry.
      def renderer_for(format, document, **options)
        most_specific_first.each do |flavor|
          next unless flavor.matches?(document.class, document)

          renderer = flavor.renderer_for(format, document, **options)
          return renderer if renderer
        end
        nil
      end

      # Canonical FLAVOR entry for a stdtype/taste name: follows the
      # base_flavor chain so compile loads the base flavor's gem and
      # processor while the taste supplies config.
      def canonical(name)
        entry = find_by_name(name)
        return nil unless entry

        entry = find_by_name(entry.base_flavor) while entry&.base_flavor
        entry
      end

      private

      # Tastes before base flavors regardless of registration order:
      # flavor gems self-register on their own load time, so a taste
      # registered first (metanorma-taste loading before the base gem)
      # would otherwise lose the reverse-order walk to its own base.
      def most_specific_first
        tastes, bases = @flavors.partition(&:taste?)
        tastes.reverse_each + bases.reverse_each
      end
    end
  end
end
