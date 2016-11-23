require 'zlib'
require 'rubygems/package'

module Dynflow
  module Exporters
    class Tar < Abstract

      FILE_MODE = 0644
      DIR_MODE = 0775

      class << self

        def full_html_export(plans)
          html = Exporters::HTML.new(plans.first.world)
          tar = self.new(html, :with_assets => true,
                         :with_index  => true,
                         :filetype    => 'html')
          tar.add_many(plans)
            .add_file('worlds.html', html.export_worlds)
            .finalize.result
        end

        def full_json_export(plans)
          tar = self.new(Exporters::JSON.new(nil, :with_sub_plans => false),
                         :filetype => 'json')
          tar.add_many(plans).finalize.result
        end

      end

      def initialize(exporter, options = {})
        @exporter = exporter
        @buffer = options.fetch(:io, StringIO.new(""))
        @gzip = Zlib::GzipWriter.new(@buffer)
        @tar = Gem::Package::TarWriter.new(@gzip)
        @options = options
      end

      def finalize
        @exporter.finalize

        add_assets if @options[:with_assets]
        add_file('index.' + @options[:filetype], @exporter.export_index) if @options[:with_index]

        @exporter.index.each do |key, value|
          add_file(key + '.' + @options[:filetype], value[:result])
        end

        @tar.close
        @gzip.close
        self
      end

      def result
        @buffer.string
      end

      def add_file(path, contents, size = contents.size)
        @tar.add_file_simple(path, FILE_MODE, size) do |stream|
          stream.write(contents)
        end
        self
      end

      def add(execution_plan)
        @exporter.add(execution_plan)
        self
      end

      def add_id(execution_plan_id)
        @exporter.add_id(execution_plan_id)
        self
      end

      def add_assets
        Dir.chdir(::Dynflow::Web.web_dir('/assets')) do
          Dir["**/*"].each do |asset|
            if File.directory?(asset)
              @tar.mkdir(asset, DIR_MODE)
            else
              add_file_path(asset)
            end
          end
        end
        self
      end

      private

      def add_file_path(path)
        File.open(path) do |f|
          add_file(path, f.read, f.size)
        end
      end
    end
  end
end
