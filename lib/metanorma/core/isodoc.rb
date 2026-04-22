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
    end
  end
end
