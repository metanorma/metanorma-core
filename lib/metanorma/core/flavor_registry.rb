# frozen_string_literal: true

module Metanorma
  module Core
    # The process-wide flavor/taste table. Registered most-specific-last;
    # resolution walks most-specific-first so flavor gems (loaded after
    # the harness defaults) win, and taste entries fall through to their
    # base chain by yielding nil.
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
        @flavors.reverse_each.find { |f| f.matches?(document.class) }
      end

      # Renderer class for (document, format): walk matching entries
      # most-specific-first; a taste without its own renderer for the
      # format yields nil and falls through to the base flavor entry.
      def renderer_for(format, document, **options)
        @flavors.reverse_each.each do |flavor|
          next unless flavor.matches?(document.class)

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
    end
  end
end
