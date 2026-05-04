# frozen_string_literal: true

require "asciidoctor"
require_relative "flavor_loader"

module Metanorma
  module Core
    # Construction and initialisation of an isodoc converter instance for a
    # given Metanorma flavor. Two entry points:
    #
    # - {.resolve_converter} — pick the right converter class for the
    #   flavor + output stage (presentation XML or HTML), instantiate it,
    #   and return a fresh, *uninitialised* converter.
    # - {.init} — wire i18n, metadata, and xref state onto an existing
    #   converter, returning it ready for use.
    #
    # Callers usually need both: +init(resolve_converter(flavor), ...)+.
    # The collection layer's +Util::isodoc_create+ is the canonical wrapper
    # around that pair.
    module Isodoc
      # Stand-in for the Asciidoctor +node+ argument that converters expect
      # when their +presentation_xml_converter+ / +html_converter+ factory
      # methods are invoked outside an actual Asciidoctor conversion. The
      # +attr+ and +attributes+ stubs return empty values so the factory
      # can run without a real document context.
      class EmptyNode
        # @param _ [String] attribute name (ignored).
        # @return [nil]
        def attr(_)
          nil
        end

        # @return [Hash] empty attribute set.
        def attributes
          {}
        end
      end

      # Initialise the i18n / metadata / xref state on an existing
      # converter. Mutates the converter in place and returns it.
      #
      # The converter must already implement the standard Metanorma
      # converter contract: +#init_i18n+, +#i18n_init+, +#metadata_init+,
      # +#meta+, +#xref_init+, +#xrefs+, and (optionally) +#info+.
      #
      # @param converter [Object] An IsoDoc-style converter instance,
      #   typically returned by {.resolve_converter}.
      # @param lang [String] BCP-47 language tag (e.g. "en").
      # @param script [String] ISO-15924 script tag (e.g. "Latn").
      # @param locale [String, nil] Optional BCP-47 locale tag for
      #   region-specific overrides.
      # @param i18nyaml [Hash, String, nil] Either a parsed i18n hash or
      #   a path to a YAML file. Forwarded to +init_i18n+.
      # @param xml [Nokogiri::XML::Node, nil] If supplied, +converter.info+
      #   is invoked against it so document-level metadata can be primed.
      # @param localdir [String, nil] If supplied, wired into both
      #   +converter.meta+ and +converter.xrefs.klass+ so file lookups
      #   resolve relative to the right directory.
      # @return [Object] the same +converter+, fully initialised.
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

      # Resolve the right IsoDoc converter for a given Metanorma flavor
      # and output stage, and return a fresh, *uninitialised* instance
      # of it. The flavor's gem (e.g. metanorma-iso) is autoloaded via
      # {Metanorma::Core::FlavorLoader.load_flavor} if it is not already
      # registered.
      #
      # @param flavor [Symbol, String] Metanorma flavor (e.g. +:iso+,
      #   +:standoc+) or a taste name resolvable to one.
      # @param presxml [Boolean] If true (default), return the flavor's
      #   presentation-XML converter; otherwise its HTML converter.
      # @return [Object] An IsoDoc-style converter instance, ready to
      #   pass to {.init}.
      # @raise [RuntimeError] If no Asciidoctor converter is registered
      #   for the resolved flavor, or if the converter does not support
      #   the requested output stage.
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
