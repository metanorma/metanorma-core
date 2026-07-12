# Registry of all Metanorma types and entry points
#

module Metanorma
  # Abstract base class for Metanorma flavor processors. Each flavor
  # gem (metanorma-iso, metanorma-itu, etc.) defines a subclass and
  # registers it with {Metanorma::Registry}; the registry then
  # dispatches input documents to the appropriate processor based on
  # the document's declared flavor / class.
  #
  # Subclasses MUST set +@short+, +@input_format+, and (if Asciidoctor
  # is the input parser) +@asciidoctor_backend+ in their +initialize+,
  # and MAY override {#output_formats}, {#use_presentation_xml},
  # {#options_preprocess}, and {#output} to customise their output
  # pipeline.
  class Processor
    # @return [Symbol] short name registered with the Registry
    #   (e.g. +:iso+, +:itu+).
    attr_reader :short

    # @return [Symbol] input parser identifier (typically +:asciidoc+).
    attr_reader :input_format

    # @return [Symbol, nil] Asciidoctor backend symbol used when the
    #   processor's input is Asciidoc (e.g. +:iso+, +:standoc+);
    #   +nil+ for non-Asciidoc inputs.
    attr_reader :asciidoctor_backend

    # @raise [RuntimeError] always — concrete flavors must override.
    def initialize
      raise "This is an abstract class!"
    end

    # Mapping of output-format name to file extension. Subclasses
    # typically extend this with HTML / Word / PDF entries.
    #
    # @return [Hash{Symbol => String}] format symbol -> file extension.
    def output_formats
      {
        xml: "xml",
        presentation: "presentation.xml",
        rxl: "rxl",
      }
    end

    # Per-format "document model" publishing specs. Override in a flavor to
    # register injected reader + transformer classes for a document-model
    # output leg (Presentation/Semantic XML -> reader -> transformer -> XML),
    # so the flavor declares two classes rather than re-implementing the
    # read/transform/serialise chain in {#output}. The classes need not live
    # in the +Metanorma::+ tree.
    #
    # Each value is a Hash with keys:
    #   :reader                  - responds to +.from_xml(String)+ -> model
    #                              (required)
    #   :transformer             - responds to +.new(model, options)+; the
    #                              instance responds to +#transform+ -> target,
    #                              and the target responds to +#to_xml+
    #                              (required)
    #   :to_xml_options          - Hash splatted into +target.to_xml(**opts)+
    #                              (default +{}+)
    #   :strip_default_namespace - strip +xmlns="..."+ before +from_xml+
    #                              (default +false+)
    #   :post_process            - callable +(xml, transformer, options)+
    #                              -> xml (default identity)
    #
    # @return [Hash{Symbol => Hash}] format symbol -> spec. Empty by default,
    #   so flavors that do not use this leg are unaffected.
    def document_transformers
      {}
    end

    # Convert an input file to Metanorma semantic XML by routing it
    # through the {Metanorma::Input::Asciidoc} processor with this
    # processor's Asciidoctor backend. Override for non-Asciidoc
    # inputs.
    #
    # @param file [String] the raw input contents.
    # @param filename [String] the source filename (used for relative
    #   path resolution in includes).
    # @param options [Hash] passthrough options for the input
    #   processor; see {Metanorma::Input::Asciidoc#process}.
    # @return [String] Metanorma semantic XML.
    def input_to_isodoc(file, filename, options = {})
      Metanorma::Input::Asciidoc.new.process(file, filename,
                                             @asciidoctor_backend, options)
    end

    # def input_to_isodoc(file, filename)
    #   raise "This is an abstract class!"
    # end

    # Whether the given output extension is downstream of the
    # presentation XML stage (and therefore needs presentation XML
    # generated first). Defaults to true for HTML/Word/PDF. Other formats
    # such as RFC and STS are generated directly from semantic XML
    #
    # @param ext [Symbol] output-format symbol.
    # @return [Boolean]
    def use_presentation_xml(ext)
      case ext
      when :html, :doc, :pdf then true
      else
        false
      end
    end

    # Mutate +options+ in place to ensure +:output_formats+ is set.
    # Override to add other flavor-specific defaults.
    #
    # @param options [Hash] processor options.
    # @return [Hash] +options+ with +:output_formats+ defaulted.
    def options_preprocess(options)
      options[:output_formats] ||= output_formats
    end

    # Default output-writer. If +format+ is registered in
    # {#document_transformers}, render it through the document-model leg
    # ({#render_via_document_model}); otherwise dump the rendered output
    # string to a UTF-8 file. Flavors override this for binary formats
    # (Word, PDF) that need different post-processing, calling +super+ for
    # the document-model and passthrough cases.
    #
    # @param isodoc_node [String, nil] rendered output content, or the
    #   semantic XML string on the document-model semantic leg.
    # @param inname [String] source filename.
    # @param outname [String] destination path.
    # @param format [Symbol] output format.
    # @param options [Hash] processor options.
    # @return [Object] bytes written (passthrough) or the serialised XML
    #   string (document-model leg).
    def output(isodoc_node, inname, outname, format, options = {})
      options_preprocess(options)
      if document_transformers.key?(format)
        render_via_document_model(isodoc_node, inname, outname, format,
                                  options)
      else
        File.open(outname, "w:UTF-8") { |f| f.write(isodoc_node) }
      end
    end

    # Render a document-model output leg: read the input XML into a model via
    # the registered reader, transform it, serialise, optionally post-process,
    # and write. The input XML comes from +isodoc_node+ (semantic leg) or,
    # when that is nil, from reading +inname+ (presentation leg) — so both
    # {#use_presentation_xml} settings are supported transparently. The driver
    # is duck-typed: it never names a concrete reader/transformer/target-model
    # gem, keeping those out of metanorma-core's dependencies.
    #
    # @param isodoc_node [String, nil] semantic XML string, or nil on the
    #   presentation leg.
    # @param inname [String] input filename (read on the presentation leg).
    # @param outname [String, nil] destination path; written when non-nil.
    # @param format [Symbol] output-format symbol; must be a key of
    #   {#document_transformers}.
    # @param options [Hash] processor options, passed to the transformer and
    #   post-processor.
    # @return [String] the serialised (and post-processed) output XML.
    def render_via_document_model(isodoc_node, inname, outname, format, options)
      spec = document_transformers.fetch(format)
      xml = document_model_input_xml(isodoc_node, inname)
      xml = xml.gsub(/\sxmlns="[^"]*"/, "") if spec[:strip_default_namespace]
      transformer = spec.fetch(:transformer)
        .new(spec.fetch(:reader).from_xml(xml), options)
      out = transformer.transform.to_xml(**(spec[:to_xml_options] || {}))
      if (post = spec[:post_process])
        out = post.call(out, transformer, options)
      end
      File.open(outname, "w:UTF-8") { |f| f.write(out) } if outname
      out
    end

    # Resolve the input XML string from whichever leg fired: the semantic
    # leg passes the XML as +isodoc_node+; the presentation leg passes nil
    # and the presentation-XML file path as +inname+.
    #
    # @param isodoc_node [String, nil] semantic XML string, or nil.
    # @param inname [String] presentation-XML file path (used when node nil).
    # @return [String] the input XML.
    def document_model_input_xml(isodoc_node, inname)
      return isodoc_node if isodoc_node

      File.read(inname, encoding: "UTF-8")
    end
    private :document_model_input_xml

    # Read processor-relevant options from the input file's header
    # via {Metanorma::Input::Asciidoc#extract_options}, merging in
    # this processor's +output_formats+ for downstream stages.
    #
    # @param file [String] raw input contents.
    # @return [Hash] extracted options.
    def extract_options(file)
      Metanorma::Input::Asciidoc.new.extract_options(file)
        .merge(output_formats: output_formats)
    end

    # Read metanorma-specific options from the input file's header
    # via {Metanorma::Input::Asciidoc#extract_metanorma_options}.
    #
    # @param file [String] raw input contents.
    # @return [Hash] metanorma-specific options
    #   (+:type+, +:extensions+, +:relaton+, +:asciimath+, +:novalid+).
    def extract_metanorma_options(file)
      Metanorma::Input::Asciidoc.new.extract_metanorma_options(file)
    end
  end
end