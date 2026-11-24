# frozen_string_literal: true

require "spec_helper"
require "metanorma-core"

RSpec.describe Metanorma::Core::Flavors, :aggregate_failures do
  let(:flavors) { described_class }
  let(:flavor_class) { Metanorma::Core::Flavor }
  let(:ladl) { ->(_model, **_options) { :labelled } }

  after do
    registered = flavors.table.instance_variable_get(:@flavors)
    registered.reject! { |f| f.name.to_s.start_with?("rspec_lbl") }
  end

  def register(**opts)
    flavors.register(flavor_class.new(**opts))
  end

  it "defaults to xref with no adapter" do
    register(name: :rspec_lbl_a)
    expect(flavors.labeler_name(:rspec_lbl_a)).to eq(:xref)
    expect(flavors.labeler_for(:rspec_lbl_a)).to be_nil
  end

  it "dispatches to the registered ladl adapter when the flavor opts in" do
    register(name: :rspec_lbl_a, labeler: :ladl, labelers: { ladl: ladl })
    expect(flavors.labeler_name(:rspec_lbl_a)).to eq(:ladl)
    expect(flavors.labeler_for(:rspec_lbl_a)).to equal(ladl)
  end

  it "lets a per-call override select xref or ladl" do
    register(name: :rspec_lbl_a, labeler: :ladl, labelers: { ladl: ladl })
    expect(flavors.labeler_for(:rspec_lbl_a, labeler: "xref")).to be_nil
    register(name: :rspec_lbl_b, labelers: { "ladl" => ladl })
    expect(flavors.labeler_for(:rspec_lbl_b, labeler: :ladl)).to equal(ladl)
  end

  it "lets a taste inherit its base flavor's labeler and adapter" do
    register(name: :rspec_lbl_a, labeler: :ladl, labelers: { ladl: ladl })
    register(name: :rspec_lbl_t, base_flavor: :rspec_lbl_a)
    expect(flavors.labeler_name(:rspec_lbl_t)).to eq(:ladl)
    expect(flavors.labeler_for(:rspec_lbl_t)).to equal(ladl)
  end

  it "lets a taste opt back to xref over its base" do
    register(name: :rspec_lbl_a, labeler: :ladl, labelers: { ladl: ladl })
    register(name: :rspec_lbl_t, base_flavor: :rspec_lbl_a, labeler: :xref)
    expect(flavors.labeler_for(:rspec_lbl_t)).to be_nil
  end

  it "fails explicitly when ladl is selected without an adapter" do
    register(name: :rspec_lbl_a, labeler: :ladl)
    expect { flavors.labeler_for(:rspec_lbl_a) }
      .to raise_error(ArgumentError, /No ladl labeler adapter/)
  end

  it "rejects unknown labelers and non-callable adapters" do
    errors = [{ labeler: :bogus }, { labelers: { ladl: 1 } }, { labelers: [] }]
      .map { |opts| build_error(opts) }
    expect(errors).to match([/Unknown labeler/, /must respond to call/,
                             /name-to-callable/])
  end

  def build_error(opts)
    flavor_class.new(name: :rspec_lbl_a, **opts)
  rescue ArgumentError => e
    e.message
  end

  it "detects circular inheritance" do
    register(name: :rspec_lbl_a, base_flavor: :rspec_lbl_b)
    register(name: :rspec_lbl_b, base_flavor: :rspec_lbl_a)
    expect { flavors.labeler_name(:rspec_lbl_a) }
      .to raise_error(ArgumentError, /Circular/)
  end
end
