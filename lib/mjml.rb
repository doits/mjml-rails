require "rails/version"
require "action_view"
require "action_view/template"
require "mjml/mjmltemplate"
require "mjml/railtie"
require "rubygems"
require "open3"

module Mjml
  mattr_accessor :template_language, :raise_render_exception, :mjml_binary_version_supported, :mjml_binary_error_string, :beautify, :minify, :validation_level

  @@template_language = :erb
  @@raise_render_exception = true
  @@mjml_binary_version_supported = "4."
  @@mjml_binary_error_string = "Couldn't find the MJML #{Mjml.mjml_binary_version_supported} binary.. have you run $ npm install mjml?"
  @@beautify = true
  @@minify = false
  @@validation_level = "soft"

  def self.check_version(bin)
    stdout, _, status = run_mjml('--version', mjml_bin: bin)
    status.success? && stdout.include?("mjml-core: #{Mjml.mjml_binary_version_supported}")
  rescue StandardError
    false
  end

  def self.run_mjml(args, mjml_bin: nil)
    mjml_bin ||= BIN

    Open3.capture3("#{mjml_bin} #{args}")
  end

  def self.discover_mjml_bin
    # Check for local install of MJML with yarn
    yarn_bin = `which yarn`.chomp
    if yarn_bin.present?
      mjml_bin = "#{yarn_bin} run mjml"
      return mjml_bin if check_version(mjml_bin)
    end

    # Check for a local install of MJML with npm
    npm_bin = `which npm`.chomp
    if npm_bin.present? && (installer_path = bin_path_from(npm_bin)).present?
      mjml_bin = File.join(installer_path, 'mjml')
      return mjml_bin if check_version(mjml_bin)
    end

    # Check for a global install of MJML
    mjml_bin = `which mjml`.chomp
    return mjml_bin if mjml_bin.present? && check_version(mjml_bin)

    puts Mjml.mjml_binary_error_string
    nil
  end

  def self.bin_path_from(package_manager)
    stdout, _, status = Open3.capture3("#{package_manager} bin")

    return unless status.success?

    stdout.chomp
  rescue Errno::ENOENT # package manager is not installed
    nil
  end

  BIN = discover_mjml_bin

  class Handler
    def template_handler
      @_template_handler ||= ActionView::Template.registered_template_handler(Mjml.template_language)
    end

    # Optional second source parameter to make it work with Rails >= 6:
    # Beginning with Rails 6 template handlers get the source of the template as the second
    # parameter.
    def call(template, source = nil)
      compiled_source =
        if Rails::VERSION::MAJOR >= 6
          template_handler.call(template, source)
        else
          template_handler.call(template)
        end

      # Per MJML v4 syntax documentation[0] valid/render'able document MUST start with <mjml> root tag
      # If we get here and template source doesn't start with one it means
      # that we are rendering partial named according to legacy naming convention (partials ending with '.mjml')
      # Therefore we skip MJML processing and return raw compiled source. It will be processed
      # by MJML library when top-level layout/template is rendered
      #
      # [0] - https://github.com/mjmlio/mjml/blob/master/doc/guide.md#mjml
      if compiled_source =~ /<mjml(.+)?>/i
        "Mjml::Mjmltemplate.to_html(begin;#{compiled_source};end).html_safe"
      else
        compiled_source
      end
    end
  end

  def self.setup
    yield self if block_given?
  end

  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.progname = self.name
      end
    end
  end
end
