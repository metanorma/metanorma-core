module Metanorma
  module Input
    # Abstract base for input processors. Concrete subclasses
    # (e.g. {Metanorma::Input::Asciidoc}) override {#process} to
    # convert raw input text into ISODoc semantic XML.
    class Base
      # @param _file [String] raw input contents.
      # @param _filename [String] source filename for relative
      #   path resolution.
      # @param _type [Symbol] target backend symbol.
      # @raise [RuntimeError] abstract base — subclasses must override.
      def process(_file, _filename, _type)
        raise "This is an abstract class"
      end
    end
  end
end
