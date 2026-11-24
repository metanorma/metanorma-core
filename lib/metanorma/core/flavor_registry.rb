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

      # Effective labeler for a flavor or taste: an explicit override, else the
      # nearest registration along the taste -> base chain. Legacy xref is the
      # default until a flavor opts in to ladl.
      def labeler_name(name, override: nil)
        explicit = Flavor.labeler_choice(override)
        return explicit if explicit

        flavor_chain(name).each do |entry|
          return entry.labeler if entry.labeler
        end
        :xref
      end

      # Adapter (callable taking the presentation model) for the effective
      # labeler. Nil for xref, which stays owned by the legacy converter; an
      # unregistered ladl adapter fails loudly rather than falling back.
      def labeler_for(name, labeler: nil)
        selected = labeler_name(name, override: labeler)
        flavor_chain(name).each do |entry|
          adapter = entry.labelers[selected]
          return adapter if adapter
        end
        return nil if selected == :xref

        raise ArgumentError,
              "No #{selected} labeler adapter registered for #{name}"
      end

      private

      def flavor_chain(name)
        chain = []
        entry = find_by_name(name)
        while entry
          circular!(chain + [entry]) if chain.include?(entry)
          chain << entry
          entry = entry.base_flavor && find_by_name(entry.base_flavor)
        end
        chain
      end

      def circular!(chain)
        names = chain.map(&:name).join(" -> ")
        raise ArgumentError, "Circular flavor inheritance: #{names}"
      end
    end
  end
end
