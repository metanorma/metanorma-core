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
      def renderer_for(format, document, flavor: nil, **options)
        entries = flavor ? flavor_chain(flavor) : most_specific_first
        if flavor && !entries.any? { |entry| entry.matches?(document.class, document) }
          return nil
        end

        entries.each do |entry|
          inherits_model = flavor && entry.taste? && entry.model_root.nil?
          next unless inherits_model || entry.matches?(document.class, document)

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
        { html_engine: :isodoc, labeler: :xref }.fetch(kind)
      end

      # LADL adapters mutate the presentation model passed to #call. The xref
      # default remains owned by the legacy converter and needs no adapter.
      def labeler_for(name, labeler: nil)
        selected = engine_for(name, kind: :labeler, override: labeler)
        flavor_chain(name).each do |entry|
          adapter = entry.labelers[selected]
          return adapter if adapter
        end
        return nil if selected == :xref

        raise ArgumentError, "No #{selected} labeler adapter registered for #{name}"
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
