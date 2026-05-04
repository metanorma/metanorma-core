# frozen_string_literal: true

require "asciidoctor"
require "nokogiri"

module Metanorma
  module Core
    # Inline-snippet boilerplate handling shared across metanorma-standoc and
    # metanorma (collection). Provides Liquid + Asciidoc substitution into
    # docidentifier-like snippets, plus the option-isolating Asciidoctor
    # convert wrapper used to keep nested conversions from leaking
    # attribute/registry state.
    #
    # Standoc Cleanup overrides {#boilerplate_snippet_cleanup} to apply its
    # namespace cleanup and footnote separation; the metanorma collection
    # caller uses the default identity hook.
    module Boilerplate
      SAFE_SHARED_ATTRIBUTES = {
        "source-highlighter" => "html-pipeline",
        "nofooter" => "",
        "no-header-footer" => "",
      }.freeze

      # @param adoc [String] Asciidoc-with-Liquid snippet
      # @param isodoc [Object] responds to populate_template, i18n
      # @return [String] localised XML/text after Liquid + Asciidoc + cleanup
      def boilerplate_snippet_convert(adoc, isodoc, lang:, script:, backend:,
                                      flush_caches: false, localdir: nil)
        b = isodoc.populate_template(adoc, nil)
        node = adoc2xml(b, backend, flush_caches: flush_caches,
                                    localdir: localdir)
        ret = boilerplate_snippet_cleanup(node)
        isodoc.i18n.l10n(ret.children.to_xml, lang, script).strip
      end

      # Extension hook. Default: identity. Standoc overrides to apply
      # boilerplate_xml_cleanup and separate_numbering_footnotes.
      def boilerplate_snippet_cleanup(node)
        node
      end

      # Wrap text in the standard headless dummy document and run an isolated
      # Asciidoctor convert for the given backend; return the //sections
      # subtree as a Nokogiri node.
      # If text is already valid XML, return it as-is (no wrapping).
      def adoc2xml(text, flavour, flush_caches: false, localdir: nil)
        Nokogiri::XML(text).root and return text
        f = flush_caches ? ":flush-caches:\n" : ""
        doc = <<~ADOC
          = X
          A
          :semantic-metadata-headless: true
          :no-isobib:
          #{f}:novalid:
          :!sectids:

          #{text}
        ADOC
        c = isolated_asciidoctor_convert(
          doc, backend: flavour, header_footer: true, localdir: localdir,
        )
        Nokogiri::XML(c).at("//xmlns:sections")
      end

      # Run Asciidoctor.convert with curated options so that no attributes,
      # base_dir, or safe-mode setting leak in from an outer conversion
      # context. Forces novalid for the inner conversion.
      #
      # `localdir` may be passed inside the options hash; standoc callers that
      # already have @localdir set on self get base_dir wired up from there.
      # The :localdir key (if present) is stripped before delegating to
      # Asciidoctor.convert.
      def isolated_asciidoctor_convert(content, options = {})
        @isolated_conversion_stack ||= []
        @isolated_conversion_stack << true
        begin
          preserved = extract_preserved_options(options)
          options = options.dup
          options.delete(:localdir)
          isolated = preserved.merge(options).merge(
            attributes: (preserved[:attributes] || {}).merge(
              "novalid" => "",
            ),
          )
          ::Asciidoctor.convert(content, isolated)
        ensure
          @isolated_conversion_stack.pop
        end
      end

      def extract_preserved_options(user_opt)
        options = {}
        options[:safe] = user_opt[:safe] if user_opt.key?(:safe)
        localdir = user_opt[:localdir] ||
          (defined?(@localdir) ? @localdir : nil)
        if localdir && !user_opt.key?(:base_dir)
          options[:base_dir] = localdir
        end
        if user_opt[:attributes].nil?
          options[:attributes] = SAFE_SHARED_ATTRIBUTES.dup
        end
        options
      end

      # Make every method callable as both Metanorma::Core::Boilerplate.method
      # (for the metanorma collection-layer caller, which doesn't include the
      # module) and as a regular public instance method (for includers like
      # Metanorma::Standoc::Cleanup).
      extend self
    end
  end
end
