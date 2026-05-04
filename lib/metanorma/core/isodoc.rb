# frozen_string_literal: true

require "asciidoctor"
require_relative "flavor_loader"

module Metanorma
  module Core
    module Isodoc
      class EmptyNode
        def attr(_)
          nil
        end

        def attributes
          {}
        end
      end

      def self.init(converter, lang:, script:, locale: nil,
                    i18nyaml: nil, xml: nil, localdir: nil)
        converter.init_i18n(i18nyaml: i18nyaml, language: lang,
                            script: script, locale: locale)
        i18n = converter.i18n_init(lang, script, locale, i18nyaml)
        converter.metadata_init(lang, script, locale, i18n)
        converter.meta.localdir = localdir if localdir
        converter.xref_init(lang, script, nil, i18n, {})
        converter.xrefs.klass.meta = converter.meta
        converter.xrefs.klass.localdir = localdir if localdir
        converter.info(xml, nil) if xml
        converter
      end

      def self.resolve_converter(flavor, presxml: true)
        resolved = Metanorma::Core::FlavorLoader.load_flavor(flavor)
        conv_class = ::Asciidoctor::Converter.for(resolved.to_s) ||
          ::Asciidoctor::Converter.for(resolved)
        conv_class or
          raise "No Asciidoctor converter registered for #{resolved}"
        conv_instance = conv_class.new(resolved.to_s, {})
        method_name = presxml ? :presentation_xml_converter : :html_converter
        conv_instance.respond_to?(method_name) or
          raise "Flavor #{resolved} does not support " \
                "#{presxml ? 'presentation XML' : 'HTML'} conversion"
        conv_instance.send(method_name, EmptyNode.new)
      end

      # Convenience wrapper combining {.resolve_converter} and {.init}:
      # resolve the converter for +flavor+ and immediately initialise it
      # with the supplied i18n / metadata kwargs. Most callers want this
      # one-stop helper rather than the two-step form.
      #
      # @param flavor [Symbol, String] flavor or taste name; resolved via
      #   {Metanorma::Core::FlavorLoader.load_flavor}.
      # @param lang [String] BCP-47 language tag (e.g. "en").
      # @param script [String] ISO-15924 script tag (e.g. "Latn").
      # @param locale [String, nil] optional BCP-47 locale tag.
      # @param i18nyaml [Hash, String, nil] either a parsed i18n hash or
      #   a path to a YAML file. Forwarded to +init_i18n+.
      # @param xml [Nokogiri::XML::Node, nil] if supplied, +converter.info+
      #   is invoked against it for metadata priming.
      # @param localdir [String, nil] wired into +converter.meta+ and
      #   +converter.xrefs.klass+ for relative file-lookup resolution.
      # @param presxml [Boolean] if true (default), return the flavor's
      #   presentation-XML converter; otherwise its HTML converter.
      # @return [Object] a fully initialised IsoDoc-style converter.
      # @see https://github.com/metanorma/metanorma/issues/558
      def self.create(flavor, lang:, script:, locale: nil, i18nyaml: nil,
                      xml: nil, localdir: nil, presxml: true)
        conv = resolve_converter(flavor, presxml: presxml)
        init(conv, lang: lang, script: script, locale: locale,
                   i18nyaml: i18nyaml, xml: xml, localdir: localdir)
      end
    end
  end
end
