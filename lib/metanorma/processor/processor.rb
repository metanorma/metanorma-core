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

    # Default output-writer: dump the rendered output string to a
    # UTF-8 file. Override for binary formats (Word, PDF) that need
    # different post-processing.
    #
    # @param isodoc_node [String] rendered output content.
    # @param _inname [String] source filename (unused at this base level).
    # @param outname [String] destination path.
    # @param _format [Symbol] output format (unused at this base level).
    # @param _options [Hash] processor options (unused at this base level).
    # @return [Integer] bytes written (Ruby's +File#write+ return).
    def output(isodoc_node, _inname, outname, _format, _options = {})
      File.open(outname, "w:UTF-8") { |f| f.write(isodoc_node) }
    end

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