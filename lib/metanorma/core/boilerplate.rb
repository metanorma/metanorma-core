# frozen_string_literal: true

require "asciidoctor"
require "nokogiri"

module Metanorma
  module Core
    # Inline-snippet boilerplate handling shared across metanorma-standoc
    # and metanorma (collection layer). Provides Liquid + inline-Asciidoc
    # substitution into docidentifier-like snippets, plus the
    # option-isolating Asciidoctor convert wrapper used to keep nested
    # conversions from leaking attribute / extension-registry state.
    #
    # Standoc's Cleanup::Boilerplate includes this module and overrides
    # {#boilerplate_snippet_cleanup} to apply standoc-specific namespace
    # cleanup and footnote separation; the metanorma collection layer
    # calls into it as module functions
    # (e.g. +Metanorma::Core::Boilerplate.docidentifier_boilerplate_isodoc+)
    # without including the module — both forms are supported via
    # +extend self+ at the bottom of this module.
    module Boilerplate
      # Asciidoctor attributes that are safe to inherit from an outer
      # conversion context into an isolated nested convert. Anything not
      # in this set is dropped.
      SAFE_SHARED_ATTRIBUTES = {
        "source-highlighter" => "html-pipeline",
        "nofooter" => "",
        "no-header-footer" => "",
      }.freeze

      # Convert a snippet of Asciidoc-with-Liquid text into the
      # localised, cleaned-up XML string suitable for substitution into
      # a surrounding document. Three stages run in order:
      #
      # 1. Liquid substitution via +isodoc.populate_template+.
      # 2. Asciidoc-to-XML conversion via {#adoc2xml} (wraps in a
      #    headless dummy document, runs an isolated Asciidoctor
      #    convert, extracts the +//sections+ subtree).
      # 3. {#boilerplate_snippet_cleanup} extension hook (default
      #    identity; standoc overrides for namespace-cleanup +
      #    footnote separation).
      # 4. Localisation via +isodoc.i18n.l10n+.
      #
      # @param adoc [String] Snippet of Asciidoc text, possibly
      #   containing Liquid expressions like
      #   +{% if seriesabbr %}{{seriesabbr}}{% endif %}+.
      # @param isodoc [#populate_template, #i18n] An isodoc converter
      #   instance. Must respond to +populate_template(text, options)+
      #   for Liquid substitution and +i18n+ (returning an object
      #   responding to +l10n(text, lang, script)+).
      # @param lang [String] BCP-47 language tag (e.g. "en") passed to
      #   +l10n+. Owned by the caller because the docidentifier-template
      #   pipeline runs outside the isodoc converter's own +@lang+
      #   state in the collection use case.
      # @param script [String] ISO-15924 script tag (e.g. "Latn"),
      #   passed to +l10n+ for the same reason as +lang+.
      # @param backend [Symbol] Asciidoctor backend symbol
      #   (e.g. +:standoc+, +:iso+). Determines which converter
      #   Asciidoctor dispatches to for the inner conversion.
      # @param flush_caches [Boolean] If true, the dummy document
      #   wrapper includes +:flush-caches:+, telling Asciidoctor to
      #   discard cached parse results before running this snippet.
      #   Standoc threads its converter-level +@flush_caches+ through
      #   here. Defaults to false.
      # @param localdir [String, nil] Filesystem path used as the inner
      #   conversion's +:base_dir+ if the caller does not supply one
      #   explicitly. Standoc passes its +@localdir+; the collection
      #   layer passes the collection's +@dirname+.
      # @return [String] The substituted, cleaned-up XML/text snippet
      #   ready to splice into the surrounding document.
      def boilerplate_snippet_convert(adoc, isodoc, lang:, script:, backend:,
                                      flush_caches: false, localdir: nil)
        b = isodoc.populate_template(adoc, nil)
        node = adoc2xml(b, backend, flush_caches: flush_caches,
                                    localdir: localdir)
        ret = boilerplate_snippet_cleanup(node)
        isodoc.i18n.l10n(ret.children.to_xml, lang, script).strip
      end

      # Extension hook invoked by {#boilerplate_snippet_convert} on the
      # output of {#adoc2xml} before localisation. Default
      # implementation is the identity. Standoc's Cleanup::Boilerplate
      # overrides it to apply boilerplate_xml_cleanup and footnote
      # renumbering; the metanorma collection layer leaves it as
      # identity (no standoc-namespace cleanup needed at that stage).
      #
      # @param node [Nokogiri::XML::Node] The +//sections+ subtree
      #   returned by Asciidoctor for the snippet.
      # @return [Nokogiri::XML::Node] The (possibly transformed) node
      #   whose children will be serialised as the snippet's output.
      def boilerplate_snippet_cleanup(node)
        node
      end

      # Iterate over every +<docidentifier @boilerplate>+ element in
      # +xmldoc+ and replace its content with the Liquid-substituted,
      # Asciidoc-rendered output. Called from standoc's cleanup
      # pipeline (post-processing semantic XML) and from the metanorma
      # collection layer (pre-processing the collection bibdata before
      # MergeBibitems hands it to Relaton — see issue
      # https://github.com/metanorma/metanorma/issues/558).
      #
      # The +@boilerplate+ attribute is removed in all matched cases;
      # substitution is performed only when its value is +"true"+.
      # The output of {#boilerplate_snippet_convert} is a serialised
      # +<sections><p>...</p></sections>+; the inner +<p>+ children
      # are spliced into the docidentifier (or the raw output if no
      # +<p>+ was produced).
      #
      # @param xmldoc [Nokogiri::XML::Document, Nokogiri::XML::Node]
      #   The document or subtree to scan.
      # @param isodoc [#populate_template, #i18n] Isodoc instance, see
      #   {#boilerplate_snippet_convert}.
      # @param lang [String] see {#boilerplate_snippet_convert}.
      # @param script [String] see {#boilerplate_snippet_convert}.
      # @param backend [Symbol] see {#boilerplate_snippet_convert}.
      # @param flush_caches [Boolean] see {#boilerplate_snippet_convert}.
      # @param localdir [String, nil] see {#boilerplate_snippet_convert}.
      # @return [Nokogiri::XML::Document, Nokogiri::XML::Node] The
      #   input +xmldoc+, mutated in place.
      def docidentifier_boilerplate_isodoc(xmldoc, isodoc, lang:, script:,
                                           backend:, flush_caches: false,
                                           localdir: nil)
        xmldoc.xpath("//docidentifier[@boilerplate]").each do |d|
          do_substitute = d["boilerplate"] == "true"
          d.delete("boilerplate")
          do_substitute or next
          id = boilerplate_snippet_convert(
            d.children.to_xml, isodoc,
            lang: lang, script: script, backend: backend,
            flush_caches: flush_caches, localdir: localdir,
          )
          p_node = Nokogiri::XML(id).at("//p")
          d.children = p_node ? p_node.children.to_xml : id
        end
        xmldoc
      end

      # Wrap +text+ in the standard headless dummy document used across
      # the metanorma stack and run an isolated Asciidoctor convert
      # against the given backend. Returns the +//sections+ subtree as
      # a Nokogiri node so callers can splice its children into a
      # surrounding document.
      #
      # If +text+ is already valid XML (root element parses), it is
      # returned verbatim — this lets callers stash pre-converted XML
      # alongside Asciidoc snippets without a special case.
      #
      # @param text [String] Asciidoc snippet, or already-converted XML.
      # @param flavour [Symbol] Asciidoctor backend.
      # @param flush_caches [Boolean] Add +:flush-caches:+ to the
      #   dummy header. See {#boilerplate_snippet_convert}.
      # @param localdir [String, nil] Forwarded to
      #   {#isolated_asciidoctor_convert} via the options hash.
      # @return [Nokogiri::XML::Node, String] +//sections+ subtree
      #   for converted Asciidoc; original +text+ if input was XML.
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

      # Run +Asciidoctor.convert+ with curated options so that
      # attributes, +base_dir+, and safe-mode setting do NOT leak in
      # from any outer conversion context. Forces +novalid+ for the
      # inner conversion. The conversion stack is tracked in
      # +@isolated_conversion_stack+ for diagnostics; the +ensure+
      # pop guarantees the marker is balanced even on exception.
      #
      # +localdir+ may be passed inside +options+ as +:localdir+; if
      # so it becomes +:base_dir+ for the inner convert (unless the
      # caller supplied an explicit +:base_dir+). The +:localdir+ key
      # is stripped before delegating to +Asciidoctor.convert+ so it
      # does not appear as an unknown option. Callers that include
      # this module from a class with +@localdir+ get +:base_dir+
      # wired up from there as a fallback.
      #
      # @param content [String] Asciidoc input.
      # @param options [Hash] Asciidoctor convert options. Recognised
      #   special key: +:localdir+ (used for +:base_dir+ defaulting
      #   and stripped before forwarding).
      # @return [String] Asciidoctor convert output.
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

      # Compute the option set carried over from outer conversion
      # state: a curated subset (+:safe+, +:base_dir+) plus the
      # SAFE_SHARED_ATTRIBUTES hash if the caller did not supply
      # +:attributes+. Caller's own option hash takes precedence
      # for everything except +"novalid"+, which the caller of
      # {#isolated_asciidoctor_convert} forces.
      #
      # @param user_opt [Hash] Caller-supplied options. Recognised:
      #   +:safe+, +:attributes+, +:base_dir+, +:localdir+.
      # @return [Hash] Preserved options to merge in front of
      #   +user_opt+ for the inner +Asciidoctor.convert+.
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

      # Make every method callable as both
      # +Metanorma::Core::Boilerplate.method+ (for the metanorma
      # collection-layer caller, which does not include the module)
      # and as a regular public instance method (for includers like
      # +Metanorma::Standoc::Cleanup::Boilerplate+).
      extend self
    end
  end
end
