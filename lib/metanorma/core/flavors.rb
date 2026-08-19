# frozen_string_literal: true

module Metanorma
  module Core
    # The composition-layer API over the flavor/taste table. Replaces
    # the former scattered mechanisms: Registry-only processor dispatch,
    # FlavorLoader.taste2flavor, CLI hand-merged dictionaries, and the
    # renderer registries the harness once carried.
    module Flavors
      class << self
        def table
          @table ||= FlavorRegistry.new
        end

        def register(flavor)
          table.register(flavor)
        end

        # Compile-time: canonical flavor entry for a stdtype name
        # (taste chains resolved), loading its gem if needed.
        def resolve(type)
          canonical = table.canonical(type)
          return nil unless canonical

          unless backends.include?(canonical.name)
            require canonical.gem
          end
          canonical
        end

        # Render-time: renderer class for (document, format).
        def renderer_for(document, format:, **options)
          table.renderer_for(format, document, **options)
        end

        def flavor_for(document)
          table.flavor_for(document)
        end

        def find(name)
          table.find_by_name(name)
        end

        # Tastes of a given base flavor (for dictionaries/projections).
        def tastes_of(base)
          table.select { |f| f.taste? && f.base_flavor == base.to_sym }
        end

        def available_tastes
          table.select(&:taste?).map(&:name)
        end

        private

        def backends
          Metanorma::Registry.instance.supported_backends
        rescue NameError
          []
        end
      end
    end
  end
end
