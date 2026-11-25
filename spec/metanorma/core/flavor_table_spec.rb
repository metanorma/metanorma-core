# frozen_string_literal: true

require "spec_helper"
require "metanorma-core"

RSpec.describe Metanorma::Core::Flavors do
  before do
    @flavor_floor = described_class.table
                                .instance_variable_get(:@flavors).length
  end

  after do
    flavors = described_class.table.instance_variable_get(:@flavors)
    flavors.pop while flavors.length > @flavor_floor
  end

  it "registers and resolves flavors" do
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    expect(described_class.find(:rspec_flavor)).not_to be_nil
    expect(described_class.renderer_for("", format: :html)).to eq(Object)
  end

  it "chains tastes to canonical flavors" do
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste, base_flavor: :rspec_flavor,
    ))
    canonical = described_class.table.canonical(:rspec_taste)
    expect(canonical.name).to eq(:rspec_flavor)
    expect(described_class.tastes_of(:rspec_flavor).map(&:name)).to eq([:rspec_taste])
  end

  it "falls through a taste without renderers to the base flavor" do
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste, base_flavor: :rspec_flavor, model_root: "String",
      renderers: { html: ->(_doc, **_o) { nil } },
    ))
    expect(described_class.renderer_for("", format: :html)).to eq(Object)
  end

  it "resolves a taste over its base regardless of registration order" do
    # Production inversion: metanorma-taste loads before the base flavor
    # gem self-registers, so the taste sits BEFORE its base in the table.
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste, base_flavor: :rspec_flavor, model_root: "String",
      renderers: { html: ->(_doc, **_o) { :taste_renderer } },
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    expect(described_class.flavor_for("").name).to eq(:rspec_taste)
    expect(described_class.renderer_for("", format: :html)).to eq(:taste_renderer)
  end

  it "falls through a base-registered-last taste without renderers" do
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste, base_flavor: :rspec_flavor, model_root: "String",
      renderers: { html: ->(_doc, **_o) { nil } },
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    expect(described_class.renderer_for("", format: :html)).to eq(Object)
  end

  it "discriminates same-base tastes by the bibdata publisher" do
    role = Struct.new(:type)
    org = Struct.new(:abbreviation)
    contributor = Struct.new(:role, :organization)
    bibdata = Struct.new(:contributor)
    bib = bibdata.new([contributor.new([role.new("author")], org.new("WMO"))])
    document = Class.new(String).new("")
    document.define_singleton_method(:bibdata) { bib }

    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste, base_flavor: :rspec_flavor, model_root: "String",
      publisher_abbr: "IALA",
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste2, base_flavor: :rspec_flavor, model_root: "String",
      publisher_abbr: "WMO",
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    expect(described_class.flavor_for(document).name).to eq(:rspec_taste2)
  end

  it "does not claim a document whose bibdata names no author abbreviation" do
    role = Struct.new(:type)
    org = Struct.new(:abbreviation)
    contributor = Struct.new(:role, :organization)
    bibdata = Struct.new(:contributor)
    bib = bibdata.new([contributor.new([role.new("author")], org.new(nil))])
    document = Class.new(String).new("")
    document.define_singleton_method(:bibdata) { bib }

    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_taste, base_flavor: :rspec_flavor, model_root: "String",
      publisher_abbr: "IALA",
    ))
    described_class.register(Metanorma::Core::Flavor.new(
      name: :rspec_flavor, model_root: "String", renderers: { html: Object },
    ))
    expect(described_class.flavor_for(document).name).to eq(:rspec_flavor)
  end
end
