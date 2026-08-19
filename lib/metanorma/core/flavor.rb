# frozen_string_literal: true

module Metanorma
  module Core
    # One entry in the flavor/taste table — the single source of truth
    # for flavor identity across the ecosystem.
    #
    # A FLAVOR entry (base_flavor nil): a document model family — model
    # root, processor, per-format renderers, pubid module, gem name.
    # A TASTE entry (base_flavor set): a config-only variant of a flavor
    # — no model of its own; it carries the publisher discriminator,
    # branding directory, and doctype map, and inherits everything else
    # through its base chain.
    #
    # renderers values: a renderer class, or a Proc resolver taking
    # (document, **options) and returning a class — flavor-owned variant
    # selection (publisher/profile/doctype). Returning nil falls through
    # to the next matching entry.
    class Flavor
      attr_reader :name, :base_flavor, :gem, :model_root, :processor,
                  :renderers, :pubid_module, :branding_dir,
                  :publisher_abbr, :doctype_map

      def initialize(name:, base_flavor: nil, gem: nil, model_root: nil,
                     processor: nil, renderers: {}, pubid_module: nil,
                     branding_dir: nil, publisher_abbr: nil, doctype_map: {})
        @name = name.to_sym
        @base_flavor = base_flavor&.to_sym
        @gem = gem || "metanorma-#{name}"
        @model_root = model_root
        @processor = processor
        @renderers = renderers
        @pubid_module = pubid_module
        @branding_dir = branding_dir
        @publisher_abbr = publisher_abbr
        @doctype_map = doctype_map
      end

      def taste? = !!base_flavor

      def renderer_for(format, document, **options)
        entry = renderers[format]
        return nil unless entry

        entry.is_a?(Proc) ? entry.call(document, **options) : entry
      end

      def matches?(document_class)
        return false unless document_class.is_a?(Class)

        root = model_root_class
        return false unless root

        !!(document_class <= root)
      end

      def model_root_class
        return nil unless model_root

        return @model_root_class if defined?(@model_root_class)

        @model_root_class = if model_root.is_a?(Class)
                              model_root
                            elsif Object.const_defined?(model_root)
                              Object.const_get(model_root)
                            end
      end

      def pubid_module_const
        return nil unless pubid_module

        Object.const_get(pubid_module.to_s)
      end
    end
  end
end
