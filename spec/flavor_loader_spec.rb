require_relative "spec_helper"
require "tmpdir"

RSpec.describe Metanorma::Core::FlavorLoader do
  describe ".stdtype2flavor_gem" do
    it "prepends metanorma- to the stdtype" do
      expect(described_class.stdtype2flavor_gem(:iso)).to eq "metanorma-iso"
      expect(described_class.stdtype2flavor_gem(:generic)).to eq "metanorma-generic"
    end
  end

  describe ".taste2flavor" do
    let(:taste_register) { Metanorma::TasteRegister.instance }

    before do
      allow(taste_register).to receive(:aliases).and_return({})
    end

    it "returns the input symbol when no alias matches" do
      expect(described_class.taste2flavor("iso")).to eq :iso
      expect(described_class.taste2flavor(:iso)).to eq :iso
    end

    it "resolves a taste alias to its canonical flavor" do
      allow(taste_register).to receive(:aliases)
        .and_return({ icc: :iso })
      expect(described_class.taste2flavor(:icc)).to eq :iso
    end

    it "accepts string input" do
      allow(taste_register).to receive(:aliases)
        .and_return({ icc: :iso })
      expect(described_class.taste2flavor("icc")).to eq :iso
    end
  end

  describe ".load_flavor" do
    let(:registry) { Metanorma::Registry.instance }
    let(:taste_register) { Metanorma::TasteRegister.instance }

    before do
      allow(taste_register).to receive(:aliases).and_return({})
    end

    it "returns canonical when backend is already registered" do
      allow(registry).to receive(:supported_backends).and_return([:iso])
      expect(described_class).not_to receive(:require)
      expect(described_class.load_flavor(:iso)).to eq :iso
    end

    it "requires the flavor gem when backend is not yet registered" do
      call_count = 0
      allow(registry).to receive(:supported_backends) do
        call_count += 1
        call_count == 1 ? [] : [:fakeflavor]
      end
      expect(described_class).to receive(:require).with("metanorma-fakeflavor")
      expect(described_class.load_flavor(:fakeflavor)).to eq :fakeflavor
    end

    context "when the flavor gem cannot be loaded" do
      before do
        allow(registry).to receive(:supported_backends).and_return([])
        allow(described_class).to receive(:require)
          .and_raise(LoadError.new("no such gem"))
      end

      it "writes an error log file and aborts" do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            expect { described_class.load_flavor(:missing) }
              .to raise_error(SystemExit)
            expect(File.exist?("#{Date.today}-error.log")).to be true
          end
        end
      end
    end

    context "when the gem loads but does not register the backend" do
      before do
        allow(registry).to receive(:supported_backends).and_return([])
        allow(described_class).to receive(:require).and_return(true)
      end

      it "aborts with a fatal log message" do
        expect { described_class.load_flavor(:mystery) }
          .to raise_error(SystemExit)
      end
    end
  end
end
