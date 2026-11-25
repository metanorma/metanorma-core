# frozen_string_literal: true

require "pathname"

module Metanorma
  module Core
    # Bridge the established converter #convert signature to the document
    # model's HTML renderer. It deliberately does not impersonate IsoDoc's
    # metadata/xref initialization: the presentation model already owns labels.
    class DocumentHtmlConverter
      attr_reader :flavor, :options

      def initialize(flavor, labeler: nil)
        @flavor = flavor
        @options = {}
        @labeler = labeler
        # Resolve eagerly: an unavailable requested engine must never silently
        # produce legacy xref output and appear to have succeeded.
        @labeler_adapter = Flavors.labeler_for(flavor, labeler: labeler)
      end

      def configure(**options)
        @options.merge!(options.reject { |_key, value| value.nil? })
        self
      end

      def convert(input_filename, file = nil, debug = false,
                  output_filename = nil)
        xml = file || File.read(input_filename, encoding: "UTF-8")
        document = parse_document(xml)
        @labeler_adapter&.call(document, **options)
        renderer = Flavors.renderer_for(document, format: :html, flavor: flavor,
                                                 **options)
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

      private

      def parse_document(xml)
        entry = Flavors.table.canonical(flavor)
        model = entry&.model_root_class
        unless model && model.respond_to?(:from_xml)
          raise ArgumentError,
                "No XML document model registered for #{flavor}"
        end
        model.from_xml(xml.respond_to?(:to_xml) ? xml.to_xml : xml)
      end
    end
  end
end
