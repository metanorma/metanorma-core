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
      def renderer_for(format, document, flavor: nil, **options)
        entries = flavor ? flavor_chain(flavor) : @flavors.reverse_each
        return nil if flavor && !entries.any? { |entry| entry.matches?(document.class) }

        entries.each do |entry|
          inherits_model = flavor && entry.taste? && entry.model_root.nil?
          next unless inherits_model || entry.matches?(document.class)

          renderer = entry.renderer_for(format, document, **options)
          return renderer if renderer
        end
        nil
      end

      # Canonical FLAVOR entry for a stdtype/taste name: follows the
      # base_flavor chain so compile loads the base flavor's gem and
      # processor while the taste supplies config.
      def canonical(name)
        chain = flavor_chain(name)
        entry = chain.last
        entry unless entry&.taste?
      end

      # Unlike #canonical this also works before the base gem registers its
      # model/processor entry, allowing FlavorLoader to require that gem.
      def canonical_name(name)
        entry = flavor_chain(name).last
        entry ? (entry.base_flavor || entry.name) : name.to_sym
      end

      # Nil means inherit. Only the effective registry lookup supplies legacy
      # defaults, so an unconfigured taste does not mask its base's choice.
      def engine_for(name, kind:, override: nil)
        explicit = Flavor.engine_choice(kind, override)
        chain = flavor_chain(name)
        return explicit if explicit

        chain.each do |entry|
          value = entry.public_send(kind)
          return value if value
        end
        { html_engine: :isodoc }.fetch(kind)
      end

      private

      def flavor_chain(name)
        chain = []
        seen = []
        entry = find_by_name(name)
        while entry
          if seen.include?(entry.name)
            raise ArgumentError,
                  "Circular flavor inheritance: #{(seen + [entry.name]).join(' -> ')}"
          end
          seen << entry.name
          chain << entry
          entry = entry.base_flavor && find_by_name(entry.base_flavor)
        end
        chain
      end
    end
  end
end
