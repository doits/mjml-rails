require "rails/version"
require "action_view"
require "action_view/template"
require "mjml/mjmltemplate"
require "mjml/railtie"
require "rubygems"
require "open3"

module Mjml
  mattr_accessor \
    :beautify,
    :minify,
    :mjml_binary,
    :mjml_binary_error_string,
    :mjml_binary_version_supported,
    :raise_render_exception,
    :template_language,
    :validation_level

  mattr_writer :valid_mjml_binary

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

  def self.run_mjml(args, mjml_bin: valid_mjml_binary)
    Open3.capture3("#{mjml_bin} #{args}")
  end

  def self.valid_mjml_binary
    @@valid_mjml_binary ||=
      check_for_custom_mjml_binary ||
      check_for_yarn_mjml_binary ||
      check_for_npm_mjml_binary ||
      check_for_global_mjml_binary

    return @@valid_mjml_binary if @@valid_mjml_binary

    puts Mjml.mjml_binary_error_string
  end

  def self.check_for_custom_mjml_binary
    if const_defined?('BIN') && Mjml::BIN.present?
      logger.warn('Setting `Mjml::BIN` is deprecated and will be removed in a future version! Please use `Mjml.mjml_binary=` instead.')
      self.mjml_binary = Mjml::BIN
      remove_const 'BIN'
    end

    return unless mjml_binary.present?

    return mjml_binary if check_version(mjml_binary)

    raise "MJML.mjml_binary is set to '#{mjml_binary}' but MJML-Rails could not validate that it is a valid MJML binary. Please check your configuration."
  end

  def self.check_for_yarn_mjml_binary
    yarn_bin = `which yarn`.chomp
    return unless yarn_bin.present?

    mjml_bin = "#{yarn_bin} run mjml"
    return mjml_bin if check_version(mjml_bin)
  end

  def self.check_for_npm_mjml_binary
    npm_bin = `which npm`.chomp
    return unless npm_bin.present? && (installer_path = bin_path_from(npm_bin)).present?

    mjml_bin = File.join(installer_path, 'mjml')
    return mjml_bin if check_version(mjml_bin)
  end

  def self.check_for_global_mjml_binary
    mjml_bin = `which mjml`.chomp
    return mjml_bin if mjml_bin.present? && check_version(mjml_bin)
  end

  def self.bin_path_from(package_manager)
    stdout, _, status = Open3.capture3("#{package_manager} bin")

    return unless status.success?

    stdout.chomp
  rescue Errno::ENOENT # package manager is not installed
    nil
  end

  def self.discover_mjml_bin
    logger.warn('`Mjml.discover_mjml_bin` is deprecated and has no effect anymore! Please use `Mjml.mjml_binary=` to set a custom MJML binary.')
  end

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
