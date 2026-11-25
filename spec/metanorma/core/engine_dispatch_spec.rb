# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "metanorma/core/document_html_converter"

RSpec.describe "flavor engine dispatch" do
  let(:registry) { Metanorma::Core::FlavorRegistry.new }

  def entry(name, **options)
    Metanorma::Core::Flavor.new(name: name, **options)
  end

  describe "registration and inheritance" do
    it "keeps nil registration values so tastes inherit opt-ins" do
      taste = entry(:taste, base_flavor: :base)
      expect(taste.html_engine).to be_nil
      expect(taste.labeler).to be_nil
      registry.register(entry(:base, html_engine: "document", labeler: "ladl"))
      registry.register(taste)
      expect(registry.engine_for(:taste, kind: :html_engine)).to eq(:document)
      expect(registry.engine_for(:taste, kind: :labeler)).to eq(:ladl)
    end

    it "uses legacy defaults for unconfigured and unregistered flavors" do
      registry.register(entry(:base))
      %i[base unregistered].each do |type|
        expect(registry.engine_for(type, kind: :html_engine)).to eq(:isodoc)
        expect(registry.engine_for(type, kind: :labeler)).to eq(:xref)
      end
    end

    it "honors a taste override and then an explicit per-call override" do
      registry.register(entry(:base, html_engine: :document, labeler: :ladl))
      registry.register(entry(:taste, base_flavor: :base,
                                    html_engine: :isodoc, labeler: :xref))
      expect(registry.engine_for(:taste, kind: :html_engine)).to eq(:isodoc)
      expect(registry.engine_for(:taste, kind: :labeler)).to eq(:xref)
      expect(registry.engine_for(:taste, kind: :html_engine,
                                        override: "document")).to eq(:document)
    end

    it "follows multiple taste levels" do
      registry.register(entry(:base, html_engine: :document))
      registry.register(entry(:middle, base_flavor: :base))
      registry.register(entry(:taste, base_flavor: :middle))
      expect(registry.engine_for(:taste, kind: :html_engine)).to eq(:document)
      expect(registry.canonical(:taste).name).to eq(:base)
      allow(Metanorma::Core::Flavors).to receive(:table).and_return(registry)
      expect(Metanorma::Core::FlavorLoader.taste2flavor(:taste)).to eq(:base)
    end

    it "rejects cycles rather than hanging while resolving a taste" do
      registry.register(entry(:a, base_flavor: :b))
      registry.register(entry(:b, base_flavor: :a))
      expect { registry.engine_for(:a, kind: :html_engine) }
        .to raise_error(ArgumentError, /a -> b -> a/)
      expect { registry.canonical(:a) }
        .to raise_error(ArgumentError, /Circular flavor inheritance/)
      expect { registry.engine_for(:a, kind: :html_engine, override: :isodoc) }
        .to raise_error(ArgumentError, /Circular flavor inheritance/)
    end

    it "rejects unsupported registration and per-call engine values" do
      expect { entry(:bad, html_engine: :other) }
        .to raise_error(ArgumentError, /Unknown html_engine/)
      expect { entry(:bad, labeler: 42) }
        .to raise_error(ArgumentError, /Unknown labeler/)
      expect { registry.engine_for(:base, kind: :html_engine, override: "") }
        .to raise_error(ArgumentError, /Unknown html_engine/)
      expect { registry.engine_for(:base, kind: :other) }
        .to raise_error(ArgumentError, /Unknown engine kind/)
    end

    it "retains incomplete-chain canonical behavior without inventing a base" do
      registry.register(entry(:taste, base_flavor: :not_loaded_yet))
      expect(registry.canonical(:taste)).to be_nil
      expect(registry.canonical_name(:taste)).to eq(:not_loaded_yet)
      registry.register(entry(:nested, base_flavor: :taste))
      allow(Metanorma::Core::Flavors).to receive(:table).and_return(registry)
      expect(Metanorma::Core::FlavorLoader.taste2flavor(:nested))
        .to eq(:not_loaded_yet)
    end
  end

  describe "named renderer selection" do
    it "stays inside the requested taste/base chain" do
      registry.register(entry(:base, model_root: String,
                                    renderers: { html: String }))
      registry.register(entry(:taste, base_flavor: :base, model_root: String,
                                     renderers: { html: ->(_doc, **) { nil } }))
      registry.register(entry(:unrelated, model_root: String,
                                         renderers: { html: Object }))
      expect(registry.renderer_for(:html, "doc", flavor: :taste)).to eq(String)
      expect(registry.renderer_for(:html, "doc")).to eq(Object)
    end

    it "threads runtime options to the taste resolver" do
      resolver = ->(_document, theme:) { theme == :custom ? String : nil }
      registry.register(entry(:taste, model_root: String,
                                     renderers: { html: resolver }))
      expect(registry.renderer_for(:html, "doc", flavor: :taste,
                                                theme: :custom)).to eq(String)
    end
  end

  describe "labeler adapter resolution" do
    it "keeps legacy xref owned by the legacy converter" do
      expect(registry.labeler_for(:base)).to be_nil
    end

    it "inherits the real callable adapter from the base flavor" do
      adapter = ->(document, **) { document }
      registry.register(entry(:base, labeler: :ladl,
                                    labelers: { "ladl" => adapter }))
      registry.register(entry(:taste, base_flavor: :base))
      expect(registry.labeler_for(:taste)).to equal(adapter)
    end

    it "fails clearly for a selected but unavailable LADL adapter" do
      registry.register(entry(:base, labeler: :ladl))
      expect { registry.labeler_for(:base) }
        .to raise_error(ArgumentError, /No ladl labeler adapter/)
    end

    it "rejects a noncallable adapter at registration" do
      expect { entry(:bad, labelers: { ladl: Object }) }
        .to raise_error(ArgumentError, /must respond to call/)
      expect { entry(:bad, labelers: nil) }
        .to raise_error(ArgumentError, /name-to-callable mapping/)
    end
  end

  describe "converter factory" do
    let(:flavors) { Metanorma::Core::Flavors }
    let(:factory) { Metanorma::Core::Isodoc }
    let(:model) do
      Class.new do
        attr_accessor :xml, :label
        def self.from_xml(xml)
          new.tap { |document| document.xml = xml }
        end
      end
    end
    let(:renderer) do
      Class.new do
        def generate_full_document(document, **)
          "<html>#{document.xml}#{document.label}</html>"
        end
      end
    end

    before do
      allow(flavors).to receive(:table).and_return(registry)
      allow(Metanorma::Core::FlavorLoader).to receive(:load_flavor)
        .with(:demo).and_return(:demo)
      registry.register(entry(:demo, html_engine: :document,
                                    model_root: model,
                                    renderers: { html: renderer }))
    end

    it "returns a document converter for an opted-in HTML request" do
      expect(factory.resolve_converter(:demo, presxml: false))
        .to be_a(Metanorma::Core::DocumentHtmlConverter)
    end

    it "keeps presentation XML on the existing Asciidoctor path" do
      legacy = double("legacy converter")
      converter = double("converter", presentation_xml_converter: legacy)
      klass = double("converter class", new: converter)
      allow(Asciidoctor::Converter).to receive(:for).with("demo").and_return(klass)
      expect(factory.resolve_converter(:demo, presxml: true)).to equal(legacy)
    end

    it "keeps an explicit legacy override on the existing HTML path" do
      legacy = double("legacy HTML")
      converter = double("converter", html_converter: legacy)
      klass = double("converter class", new: converter)
      allow(Asciidoctor::Converter).to receive(:for).with("demo").and_return(klass)
      expect(factory.resolve_converter(:demo, presxml: false,
                                             html_engine: :isodoc)).to equal(legacy)
    end

    it "initializes modern options without invoking legacy xref methods" do
      converter = factory.create(:demo, lang: "en", script: "Latn",
                                       localdir: "/some/path", presxml: false)
      expect(converter.options).to include(lang: "en", script: "Latn",
                                          localdir: "/some/path")
      expect(converter).not_to respond_to(:xref_init)
    end

    it "returns rendered HTML in debug mode without writing an output" do
      converter = factory.resolve_converter(:demo, presxml: false)
      expect(converter.convert("unused.presentation.xml", "<demo/>", true))
        .to eq("<html><demo/></html>")
    end

    it "writes the established default filename and honors an explicit path" do
      converter = factory.resolve_converter(:demo, presxml: false)
      Dir.mktmpdir do |dir|
        input = File.join(dir, "sample.presentation.xml")
        File.write(input, "<demo/>")
        converter.convert(input)
        expect(File.read(File.join(dir, "sample.html")))
          .to eq("<html><demo/></html>")
        explicit = File.join(dir, "different.html")
        converter.convert(input, "<other/>", false, explicit)
        expect(File.read(explicit)).to eq("<html><other/></html>")
      end
    end

    it "does not fall back to a generic renderer when the model is absent" do
      registry.register(entry(:demo, html_engine: :document))
      converter = factory.resolve_converter(:demo, presxml: false)
      expect { converter.convert("unused.xml", "<demo/>", true) }
        .to raise_error(ArgumentError, /No XML document model/)
    end

    it "does not silently discard content through an absent renderer" do
      registry.register(entry(:demo, html_engine: :document, model_root: model))
      converter = factory.resolve_converter(:demo, presxml: false)
      expect { converter.convert("unused.xml", "<demo/>", true) }
        .to raise_error(ArgumentError, /No document HTML renderer/)
    end

    it "rejects unavailable LADL before any apparent conversion success" do
      expect { factory.resolve_converter(:demo, presxml: false, labeler: :ladl) }
        .to raise_error(ArgumentError, /No ladl labeler adapter/)
    end

    it "calls a registered labeler on the model before document rendering" do
      adapter = ->(document, **) { document.label = "labeled" }
      registry.register(entry(:demo, html_engine: :document, labeler: :ladl,
                                    labelers: { ladl: adapter }, model_root: model,
                                    renderers: { html: renderer }))
      converter = factory.resolve_converter(:demo, presxml: false)
      expect(converter.convert("unused.xml", "<demo/>", true))
        .to eq("<html><demo/>labeled</html>")
    end

    it "does not pretend legacy presentation converters use LADL" do
      expect { factory.resolve_converter(:demo, presxml: true, labeler: :ladl) }
        .to raise_error(ArgumentError, /requires a document-model converter/)
    end
  end
end
