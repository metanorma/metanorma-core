require_relative "spec_helper"

# Minimal isodoc-shaped double for boilerplate_snippet_convert.
# - populate_template: returns the input verbatim, or applies the
#   substitutions hash if provided.
# - i18n.l10n: returns the input verbatim, or applies an injected transform.
class IsodocDouble
  attr_reader :i18n

  def initialize(substitutions: {}, l10n: nil)
    @substitutions = substitutions
    @i18n = I18nDouble.new(l10n)
  end

  def populate_template(text, _options)
    @substitutions.reduce(text) { |t, (k, v)| t.gsub(k, v) }
  end
end

class I18nDouble
  def initialize(transform)
    @transform = transform
  end

  def l10n(text, _lang, _script)
    @transform ? @transform.call(text) : text
  end
end

# A faux <sections> document we return from a stubbed Asciidoctor.convert,
# so adoc2xml's `Nokogiri::XML(c).at("//xmlns:sections")` resolves cleanly.
SECTIONS_XML = <<~XML.freeze
  <doc xmlns="http://example.com/x">
    <sections><p>SENTINEL</p></sections>
  </doc>
XML

# Includer class that overrides the cleanup hook, modelling standoc's pattern.
class BoilerplateIncluderWithOverride
  include Metanorma::Core::Boilerplate

  attr_accessor :cleanup_calls

  def boilerplate_snippet_cleanup(node)
    @cleanup_calls = (@cleanup_calls || 0) + 1
    node
  end
end

RSpec.describe Metanorma::Core::Boilerplate do
  let(:isodoc) { IsodocDouble.new }

  before do
    allow(::Asciidoctor).to receive(:convert).and_return(SECTIONS_XML)
  end

  describe ".boilerplate_snippet_convert" do
    it "Liquid-substitutes via isodoc.populate_template before Asciidoctor sees the text" do
      iso = IsodocDouble.new(
        substitutions: { "{{x}}" => "S", "{{n}}" => "97" },
      )
      seen = nil
      allow(::Asciidoctor).to receive(:convert) do |content, _opts|
        seen = content
        SECTIONS_XML
      end
      described_class.boilerplate_snippet_convert(
        "IHO {{x}}-{{n}}", iso,
        lang: "en", script: "Latn", backend: :html5,
      )
      expect(seen).to include("IHO S-97")
    end

    it "passes the backend kwarg through to Asciidoctor.convert" do
      seen = nil
      allow(::Asciidoctor).to receive(:convert) do |_content, opts|
        seen = opts
        SECTIONS_XML
      end
      described_class.boilerplate_snippet_convert(
        "X", isodoc, lang: "en", script: "Latn", backend: :standoc,
      )
      expect(seen[:backend]).to eq(:standoc)
    end

    it "applies isodoc.i18n.l10n to the cleaned output and returns the string" do
      iso = IsodocDouble.new(l10n: ->(text) { "[L10N]#{text}" })
      out = described_class.boilerplate_snippet_convert(
        "X", iso, lang: "en", script: "Latn", backend: :html5,
      )
      expect(out).to start_with("[L10N]")
      expect(out).to include("SENTINEL")
    end
  end

  describe "#boilerplate_snippet_cleanup hook" do
    it "is identity by default" do
      includer = Class.new { include Metanorma::Core::Boilerplate }.new
      node = Nokogiri::XML("<root/>").root
      expect(includer.boilerplate_snippet_cleanup(node)).to equal(node)
    end

    it "is invoked exactly once by boilerplate_snippet_convert (override path)" do
      includer = BoilerplateIncluderWithOverride.new
      includer.boilerplate_snippet_convert(
        "X", isodoc, lang: "en", script: "Latn", backend: :html5,
      )
      expect(includer.cleanup_calls).to eq(1)
    end
  end

  describe ".adoc2xml" do
    it "returns input verbatim when input is already valid XML" do
      xml = "<root xmlns='http://example.com'><p>hi</p></root>"
      expect(described_class.adoc2xml(xml, :html5)).to eq(xml)
    end

    it "wraps plain text in dummy headless document and extracts //sections" do
      seen = nil
      allow(::Asciidoctor).to receive(:convert) do |content, _opts|
        seen = content
        SECTIONS_XML
      end
      node = described_class.adoc2xml("Hello", :html5)
      expect(node).to be_a(Nokogiri::XML::Node)
      expect(node.name).to eq("sections")
      expect(seen).to include("= X")
      expect(seen).to include(":semantic-metadata-headless: true")
      expect(seen).to include("Hello")
    end

    it "adds :flush-caches: only when flush_caches: true" do
      seen = []
      allow(::Asciidoctor).to receive(:convert) do |content, _opts|
        seen << content
        SECTIONS_XML
      end
      described_class.adoc2xml("X", :html5, flush_caches: true)
      described_class.adoc2xml("X", :html5, flush_caches: false)
      expect(seen[0]).to include(":flush-caches:")
      expect(seen[1]).not_to include(":flush-caches:")
    end
  end

  describe ".isolated_asciidoctor_convert" do
    it "passes localdir as :base_dir when caller did not supply :base_dir" do
      seen = nil
      allow(::Asciidoctor).to receive(:convert) do |_content, opts|
        seen = opts
        ""
      end
      described_class.isolated_asciidoctor_convert(
        "= X", { backend: :html5 }, localdir: "/tmp/xyz",
      )
      expect(seen[:base_dir]).to eq("/tmp/xyz")
    end

    it "forces novalid attribute on the inner convert" do
      seen = nil
      allow(::Asciidoctor).to receive(:convert) do |_content, opts|
        seen = opts
        ""
      end
      described_class.isolated_asciidoctor_convert("= X", { backend: :html5 })
      expect(seen[:attributes]).to include("novalid" => "")
    end

    it "uses SAFE_SHARED_ATTRIBUTES when caller did not supply :attributes" do
      seen = nil
      allow(::Asciidoctor).to receive(:convert) do |_content, opts|
        seen = opts
        ""
      end
      described_class.isolated_asciidoctor_convert("= X", { backend: :html5 })
      expect(seen[:attributes].keys).to contain_exactly(
        "source-highlighter", "nofooter", "no-header-footer", "novalid",
      )
    end
  end
end
