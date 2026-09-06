# frozen_string_literal: true

require "spec_helper"
require "metanorma-core"

RSpec.describe Metanorma::Core::Flavors do
  after { described_class.table.instance_variable_get(:@flavors).pop }

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
end
