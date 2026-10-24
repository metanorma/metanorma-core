require_relative "spec_helper"

RSpec.describe Metanorma::Util do
  describe ".log" do
    after { Metanorma.configuration.logs = %i[warning error] }

    it "prints message for configured log types" do
      Metanorma.configuration.logs = %i[warning]
      expect { described_class.log("boom", :warning) }
        .to output("boom\n").to_stdout
    end

    it "aborts with the message on stderr when type is :fatal, " \
       "even unconfigured" do
      out = IO.popen(
        [Gem.ruby, "-Ilib", "-rmetanorma-core", "-e",
         "Metanorma.configuration.logs = []; " \
         "Metanorma::Util.log('boom', :fatal)"],
        err: [:child, :out], &:read
      )
      expect(out).to include("boom")
      expect($?).to have_attributes(exitstatus: 1)
    end
  end
end
