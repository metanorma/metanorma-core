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
                  :publisher_abbr, :doctype_map, :semantic_input

      def initialize(name:, base_flavor: nil, gem: nil, model_root: nil,
                     processor: nil, renderers: {}, pubid_module: nil,
                     branding_dir: nil, publisher_abbr: nil, doctype_map: {},
                     semantic_input: false)
        @name = name&.to_sym
        @base_flavor = base_flavor&.to_sym
        @gem = gem || "metanorma-#{name}"
        @model_root = model_root
        @processor = processor
        @renderers = renderers
        @pubid_module = pubid_module
        @branding_dir = branding_dir
        @publisher_abbr = publisher_abbr
        @doctype_map = doctype_map
        @semantic_input = semantic_input
      end

      def taste? = !!base_flavor

      def renderer_for(format, document, **options)
        entry = renderers[format]
        return nil unless entry

        entry.is_a?(Proc) ? entry.call(document, **options) : entry
      end

      def matches?(document_class, document = nil)
        return false unless document_class.is_a?(Class)

        root = model_root_class
        return false unless root
        return false unless document_class <= root
        return true unless taste? && publisher_abbr

        publisher_matches?(document)
      end

      # A taste stacked over its base shares the base's model root, so
      # the class check alone cannot discriminate: several tastes
      # (wmo, iala, icc over iho/standoc roots) match the same document
      # class. The taste's publisher abbreviation against the document
      # bibdata is the discriminator. Same reading as metanorma-taste's
      # renderer gate: first author contributor carrying a non-empty
      # organization abbreviation. A document without bibdata (probe
      # fixtures, internal probes) matches on the class check alone.
      def publisher_matches?(document)
        return true unless document.respond_to?(:bibdata)

        contributors = document.bibdata&.contributor
        return true unless contributors

        contributors.each do |c|
          roles = c.respond_to?(:role) ? Array(c.role) : []
          author = roles.any? do |r|
            (r.respond_to?(:type) ? r.type : r.to_s) == "author"
          end
          next unless author

          org = c.respond_to?(:organization) ? c.organization : nil
          next unless org

          abbrev = org.respond_to?(:abbreviation) ? org.abbreviation : nil
          abbrev = abbrev.to_s unless abbrev.is_a?(String)
          return abbrev == publisher_abbr unless abbrev.empty?
        end
        true
      end

      def model_root_class
        return @model_root_class if @model_root_class

        # Never cache a miss: the flavor gem may load after the first
        # lookup (lazy string roots resolve once the owning gem is
        # required), and a cached nil would poison every later walk.
        klass = if model_root.is_a?(Class)
                  model_root
                elsif model_root && Object.const_defined?(model_root)
                  Object.const_get(model_root)
                end
        @model_root_class = klass
        klass
      end

      def pubid_module_const
        return nil unless pubid_module

        begin
          require "pubid"
        rescue LoadError
          return nil
        end
        Object.const_get(pubid_module.to_s)
      rescue NameError
        raise ArgumentError,
              "Flavor #{name.inspect}: pubid module #{pubid_module} could "               "not be resolved — fix the flavor's registration"
      end
    end
  end
end
