require_relative "spec_helper"
require "tmpdir"

# --- test doubles for the document-model publishing leg ------------------
# A reader that records the XML string it was handed and wraps it in a model.
class DTModel
  attr_reader :src

  def initialize(src)
    @src = src
  end
end

class DTReader
  class << self
    attr_accessor :last_xml
  end

  def self.from_xml(str)
    self.last_xml = str
    DTModel.new(str)
  end
end

# Target model produced by #transform; records the to_xml kwargs it received.
class DTTarget
  def initialize(model)
    @model = model
  end

  def to_xml(**opts)
    DTTransformer.last_to_xml_options = opts
    "<out>#{@model.src}</out>"
  end
end

class DTTransformer
  class << self
    attr_accessor :last_to_xml_options
  end

  attr_reader :model, :options

  def initialize(model, options)
    @model = model
    @options = options
  end

  def transform
    DTTarget.new(@model)
  end

  # an extra instance method reachable from post_process
  def note
    "NOTE"
  end
end

class DTProcessor < Metanorma::Processor
  def initialize
    @short = :dt
  end

  def output_formats
    super.merge(dt: "dt.xml", dtmin: "dtmin.xml", plain: "plain.xml")
  end

  def document_transformers
    {
      dt: {
        reader: DTReader,
        transformer: DTTransformer,
        to_xml_options: { pretty: true },
        strip_default_namespace: true,
        post_process: lambda do |xml, transformer, options|
          "#{xml}<pp t=\"#{transformer.note}\" v=\"#{options[:validate]}\"/>"
        end,
      },
      # minimal spec: exercises the defaults (no strip, no opts, no post)
      dtmin: { reader: DTReader, transformer: DTTransformer },
    }
  end
end

RSpec.describe "Metanorma::Processor document-model leg" do
  let(:processor) { DTProcessor.new }
  around do |ex|
    Dir.mktmpdir { |d| @dir = d; ex.run }
  end
  let(:out) { File.join(@dir, "out.xml") }

  it "renders the semantic leg (isodoc_node is the XML), stripping the default namespace" do
    ret = processor.output('<r xmlns="urn:x">S</r>', "in.xml", out, :dt, {})
    expect(DTReader.last_xml).not_to include("xmlns")
    expect(DTReader.last_xml).to include("S")
    expect(ret).to include("<out>")
    expect(File.read(out)).to eq(ret)
  end

  it "renders the presentation leg (isodoc_node nil, reads inname)" do
    inp = File.join(@dir, "pres.xml")
    File.write(inp, "<r>P</r>")
    ret = processor.output(nil, inp, out, :dt, {})
    expect(DTReader.last_xml).to include("P")
    expect(File.read(out)).to eq(ret)
  end

  it "runs the post_process hook with the transformer instance and options" do
    ret = processor.output("<r>S</r>", "in.xml", out, :dt, { validate: true })
    expect(ret).to include('<pp t="NOTE" v="true"/>')
  end

  it "splats to_xml_options into the target" do
    processor.output("<r>S</r>", "in.xml", out, :dt, {})
    expect(DTTransformer.last_to_xml_options).to eq({ pretty: true })
  end

  it "applies defaults when the spec omits them (no strip, empty to_xml opts, no post)" do
    ret = processor.output('<r xmlns="u">M</r>', "in.xml", out, :dtmin, {})
    expect(DTReader.last_xml).to include("xmlns") # not stripped
    expect(DTTransformer.last_to_xml_options).to eq({})
    expect(ret).not_to include("<pp") # no post_process
  end

  it "falls back to File.write for an unregistered format (backward compatible)" do
    processor.output("RAW-BYTES", "in.xml", out, :plain, {})
    expect(File.read(out)).to eq("RAW-BYTES")
  end

  it "runs options_preprocess (defaults :output_formats)" do
    options = {}
    processor.output("<r>S</r>", "in.xml", out, :dt, options)
    expect(options[:output_formats]).to eq(processor.output_formats)
  end
end
