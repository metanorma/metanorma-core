require "nokogiri"

module Metanorma
  module Input
    # Asciidoc input processor. Wraps Asciidoctor to convert raw
    # Asciidoc source into the flavor's semantic XML, and parses the
    # document header to extract metanorma- and Asciidoctor-level
    # configuration attributes (used by {Metanorma::Processor#extract_options}
    # and friends).
    class Asciidoc < Base
      # Convert +file+ to the target backend's output by running
      # +Asciidoctor.convert+ with safe-mode and metanorma-specific
      # attributes.
      #
      # @param file [String] raw Asciidoc source.
      # @param filename [String] +docfile+ value, used by Asciidoctor
      #   for include-relative path resolution.
      # @param type [Symbol] Asciidoctor backend symbol (e.g. +:iso+,
      #   +:standoc+).
      # @param options [Hash] passthrough options. Recognised:
      #   +:log+ (Asciidoctor logger), +:novalid+ (skip validation),
      #   +:output_dir+ (forwarded as the +output_dir+ attribute).
      # @return [String] Asciidoctor convert output.
      def process(file, filename, type, options = {})
        require "asciidoctor"
        out_opts = { to_file: false, safe: :safe, backend: type,
                     header_footer: true, log: options[:log],
                     novalid: options[:novalid],
                     attributes: ["nodoc", "stem", "docfile=#{filename}",
                                  "output_dir=#{options[:output_dir]}"] }
        ::Asciidoctor.convert(file, out_opts)
      end

      # Split a raw Asciidoc file into its header and body. The header
      # is everything up to the first blank line.
      #
      # @param file [String] raw Asciidoc source.
      # @return [Array<(String, String), (nil, nil)>] +[header, body]+;
      #   +[nil, nil]+ if +file+ does not split.
      def header(file)
        ret = file.split("\n\n", 2) or return [nil, nil]
        ret[0] and ret[0] += "\n"
        [ret[0], ret[1]]
      end

      # Read metanorma-specific attributes from an Asciidoc header.
      # Supports both bare (e.g. +:document-class:+) and +mn-+ prefixed
      # forms (e.g. +:mn-document-class:+); +document-class+ and +flavor+
      # are aliases. Returns a +.compact+'d hash so absent keys are
      # omitted entirely.
      #
      # @param file [String] raw Asciidoc source (header is
      #   re-extracted internally).
      # @return [Hash] subset of the keys +:type+, +:extensions+,
      #   +:relaton+, +:asciimath+, +:novalid+.
      def extract_metanorma_options(file)
        hdr, = header(file)
        /\n:(?:mn-)?(?:document-class|flavor):\s+(?<type>\S[^\n]*)\n/ =~ hdr
        /\n:(?:mn-)?output-extensions:\s+(?<extensions>\S[^\n]*)\n/ =~ hdr
        /\n:(?:mn-)?relaton-output-file:\s+(?<relaton>\S[^\n]*)\n/ =~ hdr
        /\n(?<asciimath>:(?:mn-)?keep-asciimath:[^\n]*)\n/ =~ hdr
        /\n(?<novalid>:novalid:[^\n]*)\n/ =~ hdr
        if defined?(asciimath)
          asciimath =
            !asciimath.nil? && !/keep-asciimath:\s*false/.match?(asciimath)
        end
        asciimath = nil if asciimath == false
        {
          type: defined?(type) ? type&.strip : nil,
          extensions: defined?(extensions) ? extensions&.strip : nil,
          relaton: defined?(relaton) ? relaton&.strip : nil,
          asciimath: asciimath, novalid: !novalid.nil? || nil
        }.compact
      end

      # Normalise a bare-attribute form (e.g. +":use-xinclude:"+) so a
      # value-less attribute reads as +"true"+, while a present-value
      # attribute is left in its natural shape.
      #
      # @param attr [String, nil] line matching +":NAME:"+ ...
      # @param name [String] attribute name (without colons).
      # @return [String, nil] +"true"+ if value-less, the value
      #   otherwise; +nil+ if +attr+ was +nil+.
      def empty_attr(attr, name)
        attr&.sub(/^#{name}:\s*$/, "#{name}: true")&.sub(/^#{name}:\s+/, "")
      end

      # Asciidoc attributes whose presence is parsed as a string value
      # (no boolean default). See {#extract_options}.
      ADOC_OPTIONS =
        %w(htmlstylesheet htmlcoverpage htmlintropage scripts
           scripts-override scripts-pdf wordstylesheet i18nyaml
           standardstylesheet header wordcoverpage wordintropage
           ulstyle olstyle htmlstylesheet-override bare toclevels
           htmltoclevels doctoclevels sectionsplit base-asset-path
           body-font header-font monospace-font title-font
           align-cross-elements wordstylesheet-override ieee-dtd
           pdf-encrypt pdf-encryption-length pdf-user-password
           pdf-owner-password pdf-allow-copy-content pdf-allow-edit-content
           pdf-allow-assemble-document pdf-allow-edit-annotations
           pdf-allow-print pdf-allow-print-hq pdf-allow-fill-in-forms
           pdf-stylesheet pdf-stylesheet-override relaton-render-config
           fonts font-license-agreement pdf-allow-access-content
           pdf-encrypt-metadata iso-word-template document-scheme
           localize-number iso-word-bg-strip-color modspec-identifier-base)
          .freeze

      # Boolean Asciidoc attributes that default to +true+ if the
      # attribute is bare (no value).
      EMPTY_ADOC_OPTIONS_DEFAULT_TRUE =
        %w(data-uri-image suppress-asciimath-dup use-xinclude
           source-highlighter).freeze

      # Boolean Asciidoc attributes that default to +false+ if the
      # attribute is bare (no value).
      EMPTY_ADOC_OPTIONS_DEFAULT_FALSE =
        %w(hierarchical-assets break-up-urls-in-tables toc-figures
           toc-tables toc-recommendations).freeze

      # Convert an Asciidoc-style attribute name (kebab-case, possibly
      # ending in +-override+ or +-pdf+) into the Ruby symbol used in
      # this gem's option hashes.
      #
      # @param name [String] attribute name from Asciidoc header.
      # @return [Symbol]
      def attr_name_normalise(name)
        name.delete("-").sub(/override$/, "_override").sub(/pdf$/, "_pdf")
          .to_sym
      end

      # Read processor-relevant options from an Asciidoc header. Three
      # categories are scanned: string-valued ({ADOC_OPTIONS}), boolean
      # default-true ({EMPTY_ADOC_OPTIONS_DEFAULT_TRUE}), and boolean
      # default-false ({EMPTY_ADOC_OPTIONS_DEFAULT_FALSE}). The result
      # is +.compact+'d so absent keys are omitted.
      #
      # @param file [String] raw Asciidoc source.
      # @return [Hash{Symbol => String, Boolean}]
      def extract_options(file)
        hdr, = header(file)
        ret = ADOC_OPTIONS.each_with_object({}) do |w, acc|
          m = /\n:#{w}:\s+([^\n]+)\n/.match(hdr) or next
          acc[attr_name_normalise(w)] = m[1]&.strip
        end
        ret2 = EMPTY_ADOC_OPTIONS_DEFAULT_TRUE.each_with_object({}) do |w, acc|
          m = /\n:#{w}:([^\n]*)\n/.match(hdr) || [nil, "true"]
          acc[attr_name_normalise(w)] = (m[1].strip != "false")
        end
        ret3 = EMPTY_ADOC_OPTIONS_DEFAULT_FALSE.each_with_object({}) do |w, acc|
          m = /\n:#{w}:([^\n]*)\n/.match(hdr) || [nil, "false"]
          acc[attr_name_normalise(w)] = !["false"].include?(m[1].strip)
        end
        ret.merge(ret2).merge(ret3).compact
      end
    end
  end
end
