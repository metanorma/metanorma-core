# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "metanorma-standoc"
require "metanorma/standoc/document"
require "metanorma/html"

RSpec.describe "document HTML dispatch with native presentation models" do
  let(:xml) do
    <<~XML
      <metanorma xmlns="https://www.metanorma.org/ns/standoc" type="presentation">
        <bibdata type="standard"><title language="en">Dispatch candidate</title><docidentifier>TEST 1</docidentifier><language>en</language><script>Latn</script></bibdata>
        <sections><clause id="scope"><fmt-title>1 Scope</fmt-title><p id="sample">Document engine integration sentinel</p></clause></sections>
      </metanorma>
    XML
  end

  def converter(type = :standoc)
    Metanorma::Core::Isodoc.create(type, presxml: false, html_engine: :document,
                                  lang: "en", script: "Latn")
  end

  it "uses the actual typed model and HTML renderer with already formatted labels" do
    document = Metanorma::Standoc::Document::Root.from_xml(xml)
    expect(Metanorma::Core::Flavors.renderer_for(document, format: :html, flavor: :standoc))
      .to eq(Metanorma::Html::StandardRenderer)
    html = converter.convert("unused.presentation.xml", xml, true)
    expect(html).to include("<html", "Document engine integration sentinel", "1 Scope")
  end

  it "accepts the established Nokogiri document input without changing model labels" do
    html = converter.convert("unused.presentation.xml", Nokogiri::XML(xml), true)
    expect(html).to include("Document engine integration sentinel", "1 Scope")
  end

  it "reads the input file and keeps the established default output filename" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "sample.presentation.xml")
      File.write(input, xml)
      html = converter.convert(input)
      expect(File.read(File.join(dir, "sample.html"))).to eq(html)
      expect(html).to include("Document engine integration sentinel")
    end
  end

  it "honors an explicit output filename with the established four positional arguments" do
    Dir.mktmpdir do |dir|
      output = File.join(dir, "chosen.html")
      html = converter.convert("unused.presentation.xml", xml, false, output)
      expect(File.read(output)).to eq(html)
    end
  end

  it "rejects semantic XML instead of emitting apparently successful presentation HTML" do
    semantic = xml.sub('type="presentation"', 'type="semantic"').gsub(/<fmt-title>.*?<\/fmt-title>/, '')
    expect { converter.convert("unused.xml", semantic, true) }
      .to raise_error(ArgumentError, /Presentation XML/)
  end

  it "resolves real HTML through an inherited model across multiple taste levels" do
    registry = Metanorma::Core::FlavorRegistry.new
    registry.register(Metanorma::Core::Flavors.find(:standoc))
    registry.register(Metanorma::Core::Flavor.new(name: :dispatch_parent,
      base_flavor: :standoc, html_engine: :document))
    registry.register(Metanorma::Core::Flavor.new(name: :dispatch_child,
      base_flavor: :dispatch_parent))
    allow(Metanorma::Core::Flavors).to receive(:table).and_return(registry)
    inherited = Metanorma::Core::Isodoc.create(:dispatch_child, presxml: false,
      lang: "en", script: "Latn")
    expect(inherited).to be_a(Metanorma::Core::DocumentHtmlConverter)
    expect(inherited.convert("unused.xml", xml, true)).to include("Document engine integration sentinel")
  end

  it "keeps the actual legacy HTML converter as the unconfigured default" do
    expect(Metanorma::Core::Isodoc.resolve_converter(:standoc, presxml: false))
      .not_to be_a(Metanorma::Core::DocumentHtmlConverter)
  end

  describe "review fixes" do
    around do |ex|
      saved = Metanorma::Core::Flavors.table
      reg = Metanorma::Core::FlavorRegistry.new
      reg.register(Metanorma::Core::Flavors.find(:standoc))
      Metanorma::Core::Flavors.instance_variable_set(:@table, reg)
      ex.run
    ensure
      Metanorma::Core::Flavors.instance_variable_set(:@table, saved)
    end

    it "passes only renderer-scoped options to a strict resolver" do
      Metanorma::Core::Flavors.register(Metanorma::Core::Flavor.new(
        name: :strict, base_flavor: :standoc, html_engine: :document,
        renderers: { html: ->(_d, theme: nil) { Metanorma::Html::StandardRenderer } }
      ))
      html = converter(:strict).convert("u.presentation.xml", xml, true)
      expect(html).to include("Document engine integration sentinel")
    end

    it "parses with the taste's own model_root" do
      root = Class.new(Metanorma::Standoc::Document::Root)
      renderer = Class.new do
        define_method(:generate_full_document) { |d, **| d.class.name.to_s + d.class.superclass.name }
      end
      Metanorma::Core::Flavors.register(Metanorma::Core::Flavor.new(
        name: :own, base_flavor: :standoc, html_engine: :document,
        model_root: root, renderers: { html: renderer }
      ))
      out = converter(:own).convert("u.xml", xml, true)
      expect(out).to include("Metanorma::Standoc::Document::Root")
      expect(Metanorma::Core::Flavors.model_root_class_for(:own)).to eq(root)
    end

    it "raises NotImplementedError naming the engine for collection methods" do
      conv = converter
      %i[populate_template docid_prefix info meta xref_init].each do |m|
        expect { conv.public_send(m) }
          .to raise_error(NotImplementedError, /document HTML engine/)
      end
    end
  end
end
