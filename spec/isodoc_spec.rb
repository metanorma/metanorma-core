require_relative "spec_helper"

RSpec.describe Metanorma::Core::Isodoc do
  describe Metanorma::Core::Isodoc::EmptyNode do
    it "returns nil for any attr" do
      expect(described_class.new.attr(:whatever)).to be_nil
    end

    it "returns an empty hash for attributes" do
      expect(described_class.new.attributes).to eq({})
    end
  end

  describe ".init" do
    let(:meta) { Struct.new(:localdir).new }
    let(:xrefs_klass) { Struct.new(:meta, :localdir).new }
    let(:xrefs) { Struct.new(:klass).new(xrefs_klass) }
    let(:i18n) { Object.new }
    let(:converter) do
      c = spy("converter", i18n_init: i18n, meta: meta, xrefs: xrefs)
      allow(c).to receive(:init_i18n)
      allow(c).to receive(:metadata_init)
      allow(c).to receive(:xref_init)
      allow(c).to receive(:info)
      c
    end

    it "initializes i18n, metadata, and xrefs in order" do
      described_class.init(converter, lang: "en", script: "Latn")
      expect(converter).to have_received(:init_i18n).with(
        i18nyaml: nil, language: "en", script: "Latn", locale: nil,
      ).ordered
      expect(converter).to have_received(:i18n_init)
        .with("en", "Latn", nil, nil).ordered
      expect(converter).to have_received(:metadata_init)
        .with("en", "Latn", nil, i18n).ordered
      expect(converter).to have_received(:xref_init)
        .with("en", "Latn", nil, i18n, {}).ordered
    end

    it "sets localdir on meta and xrefs.klass when given" do
      described_class.init(converter, lang: "en", script: "Latn",
                                      localdir: "/tmp/d")
      expect(converter.meta.localdir).to eq "/tmp/d"
      expect(converter.xrefs.klass.localdir).to eq "/tmp/d"
    end

    it "skips localdir assignment when not given" do
      described_class.init(converter, lang: "en", script: "Latn")
      expect(converter.meta.localdir).to be_nil
      expect(converter.xrefs.klass.localdir).to be_nil
    end

    it "calls info(xml, nil) when xml is given" do
      xml = double("xml")
      described_class.init(converter, lang: "en", script: "Latn", xml: xml)
      expect(converter).to have_received(:info).with(xml, nil)
    end

    it "does not call info when xml is omitted" do
      described_class.init(converter, lang: "en", script: "Latn")
      expect(converter).not_to have_received(:info)
    end

    it "forwards i18nyaml to init_i18n and i18n_init" do
      described_class.init(converter, lang: "en", script: "Latn",
                                      i18nyaml: "/path/i18n.yaml")
      expect(converter).to have_received(:init_i18n).with(
        i18nyaml: "/path/i18n.yaml", language: "en",
        script: "Latn", locale: nil,
      )
      expect(converter).to have_received(:i18n_init)
        .with("en", "Latn", nil, "/path/i18n.yaml")
    end

    it "returns the converter" do
      expect(described_class.init(converter, lang: "en", script: "Latn"))
        .to equal(converter)
    end
  end

  describe ".resolve_converter" do
    let(:isodoc_instance) { double("isodoc") }
    let(:converter_instance) do
      c = double("converter")
      allow(c).to receive(:presentation_xml_converter)
        .and_return(isodoc_instance)
      allow(c).to receive(:html_converter).and_return(isodoc_instance)
      c
    end
    let(:converter_class) do
      klass = Class.new
      allow(klass).to receive(:new).and_return(converter_instance)
      klass
    end

    before do
      allow(Metanorma::Core::FlavorLoader).to receive(:load_flavor)
        .with(:demo).and_return(:demo)
      allow(::Asciidoctor::Converter).to receive(:for).and_return(nil)
      allow(::Asciidoctor::Converter).to receive(:for).with("demo")
        .and_return(converter_class)
    end

    it "returns presentation xml converter via Asciidoctor::Converter.for" do
      expect(described_class.resolve_converter(:demo, presxml: true))
        .to equal(isodoc_instance)
      expect(converter_instance).to have_received(:presentation_xml_converter)
        .with(instance_of(Metanorma::Core::Isodoc::EmptyNode))
    end

    it "returns html converter when presxml is false" do
      described_class.resolve_converter(:demo, presxml: false)
      expect(converter_instance).to have_received(:html_converter)
        .with(instance_of(Metanorma::Core::Isodoc::EmptyNode))
    end

    it "raises when no Asciidoctor converter is registered" do
      allow(::Asciidoctor::Converter).to receive(:for).with("demo")
        .and_return(nil)
      allow(::Asciidoctor::Converter).to receive(:for).with(:demo)
        .and_return(nil)
      expect { described_class.resolve_converter(:demo) }
        .to raise_error(/No Asciidoctor converter registered/)
    end

    it "raises when the flavor does not support the requested conversion" do
      allow(converter_instance).to receive(:respond_to?)
        .with(:presentation_xml_converter).and_return(false)
      expect { described_class.resolve_converter(:demo, presxml: true) }
        .to raise_error(/does not support presentation XML/)
    end
  end

  describe ".create" do
    let(:converter) do
      c = double("converter")
      meta = double("meta")
      allow(meta).to receive(:localdir=)
      xrefs = double("xrefs")
      klass = double("klass")
      allow(klass).to receive(:meta=)
      allow(klass).to receive(:localdir=)
      allow(xrefs).to receive(:klass).and_return(klass)
      allow(c).to receive(:init_i18n)
      allow(c).to receive(:i18n_init).and_return(double("i18n"))
      allow(c).to receive(:metadata_init)
      allow(c).to receive(:meta).and_return(meta)
      allow(c).to receive(:xref_init)
      allow(c).to receive(:xrefs).and_return(xrefs)
      allow(c).to receive(:info)
      c
    end

    it "resolves the converter for the flavor and initialises it" do
      allow(described_class).to receive(:resolve_converter)
        .with(:demo, presxml: true).and_return(converter)
      result = described_class.create(:demo, lang: "en", script: "Latn")
      expect(described_class).to have_received(:resolve_converter)
        .with(:demo, presxml: true)
      expect(converter).to have_received(:init_i18n)
      expect(result).to equal(converter)
    end

    it "forwards locale, i18nyaml, xml, localdir kwargs through to init" do
      allow(described_class).to receive(:resolve_converter).and_return(converter)
      xml = double("xml")
      described_class.create(:demo, lang: "en", script: "Latn",
                                    locale: "GB", i18nyaml: "/p.yaml",
                                    xml: xml, localdir: "/dir")
      expect(converter).to have_received(:init_i18n).with(
        i18nyaml: "/p.yaml", language: "en", script: "Latn", locale: "GB",
      )
      expect(converter.meta).to have_received(:localdir=).with("/dir")
      expect(converter).to have_received(:info).with(xml, nil)
    end

    it "honours presxml: false on resolve_converter" do
      allow(described_class).to receive(:resolve_converter)
        .with(:demo, presxml: false).and_return(converter)
      described_class.create(:demo, lang: "en", script: "Latn",
                                    presxml: false)
      expect(described_class).to have_received(:resolve_converter)
        .with(:demo, presxml: false)
    end
  end
end
