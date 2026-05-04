module Metanorma
  # Asciidoctor extensions registered globally when metanorma-core is
  # loaded. Provides the +include::pattern[]+ glob support used across
  # the metanorma stack.
  module AsciidoctorExtensions
    # Asciidoctor +IncludeProcessor+ that expands glob patterns in
    # +include::+ directives. When the +target+ contains a +*+, the
    # files matching the glob (relative to the including reader's
    # +dir+) are included in reverse-sorted order, each separated
    # from the next by a blank line unless the +adjoin-option+
    # attribute is set.
    #
    # @example In an Asciidoc document
    #   include::sections/*.adoc[]
    class GlobIncludeProcessor < ::Asciidoctor::Extensions::IncludeProcessor
      # @param _doc [Asciidoctor::Document] containing document (unused).
      # @param reader [Asciidoctor::Reader] the include site's reader.
      # @param target_glob [String] glob pattern relative to
      #   +reader.dir+.
      # @param attributes [Hash] include directive attributes;
      #   recognises +"adjoin-option"+ to suppress the inter-file
      #   blank line.
      # @return [Asciidoctor::Reader] the reader, mutated in place.
      def process(_doc, reader, target_glob, attributes)
        Dir[File.join reader.dir, target_glob].sort.reverse_each do |target|
          content = File.readlines target
          content.unshift "" unless attributes["adjoin-option"]
          reader.push_include content, target, target, 1, attributes
        end
        reader
      end

      # Whether this processor handles the given include +target+.
      # Triggers on any target containing +*+ — sufficient for the
      # glob patterns the metanorma stack uses.
      #
      # @param target [String] include directive target.
      # @return [Boolean]
      def handles?(target)
        target.include? "*"
      end
    end
  end
end

Asciidoctor::Extensions.register do
  include_processor ::Metanorma::AsciidoctorExtensions::GlobIncludeProcessor
end
