require 'test_helper'

describe Mjml::Parser do
  let(:input) { mock('input') }
  let(:parser) { Mjml::Parser.new(input) }

  describe '#render' do
    describe 'when execption is raised' do
      let(:custom_error_class) { Class.new(StandardError) }
      let(:error) { custom_error_class.new('custom error') }

      before do
        parser.stubs(:run).raises(error)
      end

      it 'raises exception with render exception enabled' do
        with_settings(raise_render_exception: true) do
          err = expect { parser.render }.must_raise(custom_error_class)
          expect(err.message).must_equal error.message
        end
      end

      it 'returns empty string with exception raising disabled' do
        with_settings(raise_render_exception: false) do
          expect(parser.render).must_equal ''
        end
      end
    end

    describe 'can read beautify, minify, and validation_level configs' do
      it 'uses defaults if no config is set' do
        expect(Mjml.beautify).must_equal(true)
        expect(Mjml.minify).must_equal(false)
        expect(Mjml.validation_level).must_equal('strict')
      end

      it 'uses setup config' do
        Mjml.setup do |config|
          config.beautify = false
          config.minify = true
          config.validation_level = 'soft'
        end

        expect(Mjml.beautify).must_equal(false)
        expect(Mjml.minify).must_equal(true)
        expect(Mjml.validation_level).must_equal('soft')

        Mjml.setup do |config|
          config.beautify = true
          config.minify = false
          config.validation_level = 'strict'
        end
      end
    end
  end

  describe '#run' do
    describe 'when shell command failed' do
      it 'raises exception' do
        err = expect { parser.run "/tmp/non_existent_file.mjml" }.must_raise(Mjml::Parser::ParseError)
        expect(err.message).must_include 'Command line error'
      end
    end
  end
end
