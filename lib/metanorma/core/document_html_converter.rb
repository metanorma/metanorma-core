# frozen_string_literal: true

require "pathname"

module Metanorma
  module Core
    # Bridge the established converter #convert signature to the document
    # model's HTML renderer. It deliberately does not impersonate IsoDoc's
    # metadata/xref initialization: the presentation model already owns labels.
    class DocumentHtmlConverter
      # Options a renderer resolver proc may receive. Everything else
      # (lang, script, localdir...) goes to the renderer's own call only.
      RESOLVER_OPTIONS = %i[theme].freeze

      # Methods the legacy IsoDoc converter offers and collection rendering
      # relies on; the document engine does not implement them.
      LEGACY_COLLECTION_METHODS = %i[
        populate_template docid_prefix info meta xrefs xref_init
        metadata_init i18n_init init_i18n
      ].freeze

      attr_reader :flavor, :options

      def initialize(flavor)
        @flavor = flavor
        @options = {}
      end

      def configure(**options)
        @options.merge!(options.reject { |_key, value| value.nil? })
        self
      end

      def convert(input_filename, file = nil, debug = false,
                  output_filename = nil)
        xml = file || File.read(input_filename, encoding: "UTF-8")
        document = parse_document(xml)
        renderer = Flavors.renderer_for(
          document, format: :html, flavor: flavor,
                    **options.slice(*RESOLVER_OPTIONS)
        )
        unless renderer
          raise ArgumentError,
                "No document HTML renderer registered for #{flavor}"
        end

        html = renderer.new.generate_full_document(document, **options)
        return html if debug

        output_filename ||= Pathname.new(input_filename).sub_ext("")
          .sub(/\.presentation$/, "").to_s + ".html"
        File.write(output_filename, html, encoding: "UTF-8")
        html
      end

      # Not advertised via respond_to?: the document converter does not
      # implement these; calling one explains why.
      def method_missing(name, *args, &block)
        return super unless LEGACY_COLLECTION_METHODS.include?(name)

        raise NotImplementedError,
              "#{self.class.name}##{name} is not available with the " \
              "document HTML engine (flavor #{flavor.inspect}); " \
              "collection rendering needs the legacy IsoDoc converter " \
              "(html_engine: :isodoc)"
      end

      def respond_to_missing?(name, include_private = false)
        super
      end

      private

      def parse_document(xml)
        model = Flavors.model_root_class_for(flavor)
        unless model && model.respond_to?(:from_xml)
          raise ArgumentError,
                "No XML document model registered for #{flavor}"
        end
        model.from_xml(xml.respond_to?(:to_xml) ? xml.to_xml : xml)
      end
    end
  end
end
